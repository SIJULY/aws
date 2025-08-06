import boto3, os, threading, time, queue, json, logging
from botocore.exceptions import ClientError
from botocore.config import Config
from flask import Flask, render_template, jsonify, request, session, g, redirect, url_for
from functools import wraps

app = Flask(__name__)
app.secret_key = 'a50f8376d3a1bebcc916dbdd5c08694a' # 请确保这里是您自己生成的固定Key
PASSWORD = "050148Sq$" # 【重要】请在这里设置您自己的登录密码！

KEY_FILE = "key.txt"
QUOTA_CODE = 'L-1216C47A'
QUOTA_REGION = 'us-east-1'
REGION_MAPPING = {
    "us-east-2": "us-east-2 (美国东部（俄亥俄州）)", "us-east-1": "us-east-1 (美国东部（弗吉尼亚州北部）)",
    "us-west-1": "us-west-1 (美国西部（加利福尼亚北部）)", "us-west-2": "us-west-2 (美国西部（俄勒冈州）)",
    "af-south-1": "af-south-1 (非洲（开普敦）)", "ap-east-1": "ap-east-1 (亚太地区（香港）)",
    "ap-south-1": "ap-south-1 (亚太地区（孟买）)", "ap-northeast-2": "ap-northeast-2 (亚太地区（首尔）)",
    "ap-southeast-1": "ap-southeast-1 (亚太地区（新加坡）)", "ap-southeast-2": "ap-southeast-2 (亚太地区（悉尼）)",
    "ap-northeast-1": "ap-northeast-1 (亚太地区（东京）)", "ca-central-1": "ca-central-1 (加拿大（中部）)",
    "eu-central-1": "eu-central-1 (欧洲地区（法兰克福）)", "eu-west-1": "eu-west-1 (欧洲地区（爱尔兰）)",
    "eu-west-2": "eu-west-2 (欧洲地区（伦敦）)", "eu-west-3": "eu-west-3 (欧洲地区（巴黎）)",
    "eu-north-1": "eu-north-1 (欧洲地区（斯德哥尔摩）)", "sa-east-1": "sa-east-1 (南美洲（圣保罗）)"
}
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s:%(name)s:%(message)s')
task_logs = {}

def get_boto_config(): return Config(connect_timeout=15, retries={'max_attempts': 2})

def load_keys(keyfile):
    if not os.path.exists(keyfile): return []
    with open(keyfile, "r", encoding="utf-8") as f:
        # The := is a "walrus operator", requires Python 3.8+
        return [{"name": p[0], "access_key": p[1], "secret_key": p[2]} for line in f if len(p := line.strip().split("----")) == 3]

def save_keys(keyfile, keys):
    with open(keyfile, "w", encoding="utf-8") as f:
        for key in keys: f.write(f"{key['name']}----{key['access_key']}----{key['secret_key']}\n")

def log_task(task_id, message):
    if task_id not in task_logs: task_logs[task_id] = queue.Queue()
    task_logs[task_id].put(message)

def handle_aws_error(e, task_id=None):
    error_message = f"AWS API 错误: {e}"
    if isinstance(e, ClientError):
        error_code = e.response.get("Error", {}).get("Code")
        error_message = f"AWS API 错误: {error_code} - {e.response.get('Error', {}).get('Message')}"
    logging.error(f"Task({task_id}): {error_message}")
    if task_id: log_task(task_id, f"--- 任务失败: {error_message} ---")
    return error_message

def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if "user_logged_in" not in session:
            return redirect(url_for('login')) if not request.path.startswith('/api/') else jsonify({"error": "用户未登录"}), 401
        return f(*args, **kwargs)
    return decorated_function

def aws_login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'aws_access_key_id' not in session: return jsonify({"error": "请先选择一个AWS账户"}), 403
        g.aws_access_key_id, g.aws_secret_access_key = session['aws_access_key_id'], session['aws_secret_access_key']
        return f(*args, **kwargs)
    return decorated_function

def create_instance_task(service, task_id, access_key, secret_key, region, instance_type, user_data):
    log_task(task_id, f"{service.upper()} 任务启动: 区域 {region}, 类型/套餐 {instance_type}")
    try:
        if service == 'ec2':
            client = boto3.client('ec2', region_name=region, aws_access_key_id=access_key, aws_secret_access_key=secret_key, config=get_boto_config())
            images = client.describe_images(Owners=['136693071363'], Filters=[{'Name': 'name', 'Values': ['debian-12-amd64-*']}, {'Name': 'state', 'Values': ['available']}])
            if not images['Images']: raise Exception("未找到Debian 12的AMI")
            ami_id = sorted(images['Images'], key=lambda x: x['CreationDate'], reverse=True)[0]['ImageId']
            log_task(task_id, f"使用AMI: {ami_id}")
            instance = client.run_instances(ImageId=ami_id, InstanceType=instance_type, MinCount=1, MaxCount=1, UserData=user_data)
            instance_id = instance['Instances'][0]['InstanceId']
            log_task(task_id, f"实例请求已发送, ID: {instance_id}")
            waiter = client.get_waiter('instance_running')
            waiter.wait(InstanceIds=[instance_id])
            desc = client.describe_instances(InstanceIds=[instance_id])
            ip = desc['Reservations'][0]['Instances'][0].get('PublicIpAddress', 'N/A')
            log_task(task_id, f"实例 {instance_id} 已运行, 公网 IP: {ip}")
        elif service == 'lightsail':
            client = boto3.client('lightsail', region_name=region, aws_access_key_id=access_key, aws_secret_access_key=secret_key, config=get_boto_config())
            blueprints = client.get_blueprints()
            debian_blueprints = sorted([bp for bp in blueprints['blueprints'] if 'debian' in bp['id'] and bp['isActive']], key=lambda x: x['version'], reverse=True)
            if not debian_blueprints: raise Exception("未找到可用的Debian蓝图")
            blueprint_id = debian_blueprints[0]['blueprintId']
            log_task(task_id, f"使用蓝图: {blueprint_id}")
            instance_name = f"lightsail-{region}-{int(time.time())}"
            client.create_instances(instanceNames=[instance_name], availabilityZone=f"{region}a", blueprintId=blueprint_id, bundleId=instance_type, userData=user_data)
            log_task(task_id, f"实例 {instance_name} 创建请求已发送。")
        log_task(task_id, "--- 任务完成 ---")
    except Exception as e:
        handle_aws_error(e, task_id)

def activate_region_task(task_id, access_key, secret_key, region):
    log_task(task_id, f"开始激活区域 {region}...")
    try:
        client = boto3.client('account', region_name='us-east-1', aws_access_key_id=access_key, aws_secret_access_key=secret_key, config=get_boto_config())
        client.enable_region(RegionName=region)
        log_task(task_id, f"区域 {region} 激活请求已成功提交。配置过程可能需要几分钟。")
        log_task(task_id, "--- 任务完成 ---")
    except Exception as e: handle_aws_error(e, task_id)

def query_all_instances_task(task_id, access_key, secret_key):
    log_task(task_id, "开始查询所有已激活区域的实例...")
    try:
        ec2_client_main = boto3.client('ec2', region_name='us-east-1', aws_access_key_id=access_key, aws_secret_access_key=secret_key, config=get_boto_config())
        response = ec2_client_main.describe_regions(Filters=[{'Name': 'opt-in-status', 'Values': ['opt-in-not-required', 'opted-in']}])
        enabled_regions = [r['RegionName'] for r in response['Regions']]
        log_task(task_id, f"将要查询的区域: {', '.join(enabled_regions)}")
        total_found = 0
        for region in enabled_regions:
            log_task(task_id, f"正在查询区域: {region}...")
            try:
                ec2_client = boto3.client('ec2', region_name=region, aws_access_key_id=access_key, aws_secret_access_key=secret_key, config=get_boto_config())
                for r in ec2_client.describe_instances(Filters=[{'Name':'instance-state-name','Values':['pending','running','stopped']}])['Reservations']:
                    for i in r['Instances']:
                        instance_data = {"type": "EC2", "region": region, "id": i['InstanceId'], "name": next((t['Value'] for t in i.get('Tags',[]) if t['Key'] == 'Name'), i['InstanceId']), "state": i['State']['Name'], "ip": i.get('PublicIpAddress', 'N/A')}
                        log_task(task_id, "FOUND_INSTANCE::" + json.dumps(instance_data)); total_found += 1
            except Exception as e: log_task(task_id, f"查询EC2实例失败({region}): {handle_aws_error(e)}")
            try:
                lightsail_client = boto3.client('lightsail', region_name=region, aws_access_key_id=access_key, aws_secret_access_key=secret_key, config=get_boto_config())
                for i in lightsail_client.get_instances()['instances']:
                    instance_data = {"type": "Lightsail", "region": region, "id": i['name'], "name": i['name'], "state": i['state']['name'], "ip": i.get('publicIpAddress', 'N/A')}
                    log_task(task_id, "FOUND_INSTANCE::" + json.dumps(instance_data)); total_found += 1
            except Exception as e: log_task(task_id, f"查询Lightsail实例失败({region}): {handle_aws_error(e)}")
        log_task(task_id, f"所有区域查询完毕，共找到 {total_found} 个实例。"); log_task(task_id, "--- 任务完成 ---")
    except Exception as e: handle_aws_error(e, task_id)

@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        if request.form.get("password") == PASSWORD:
            session["user_logged_in"] = True; return redirect(url_for('index'))
        else:
            return render_template("login.html", error="密码错误")
    return render_template("login.html")

@app.route("/logout")
def logout():
    session.clear(); return redirect(url_for('login'))

@app.route("/")
@login_required
def index(): return render_template("index.html")

@app.route("/api/accounts", methods=["GET", "POST"])
@login_required
def manage_accounts():
    if request.method == "GET": return jsonify([{"name": k["name"]} for k in load_keys(KEY_FILE)])
    data = request.json; keys = load_keys(KEY_FILE)
    if any(k['name'] == data['name'] for k in keys): return jsonify({"error": "账户名称已存在"}), 400
    keys.append(data); save_keys(KEY_FILE, keys)
    return jsonify({"success": True, "name": data['name']}), 201

@app.route("/api/accounts/<name>", methods=["DELETE"])
@login_required
def delete_account(name):
    keys = load_keys(KEY_FILE); keys_to_keep = [k for k in keys if k['name'] != name]
    if len(keys) == len(keys_to_keep): return jsonify({"error": "账户未找到"}), 404
    save_keys(KEY_FILE, keys_to_keep)
    if session.get('account_name') == name: 
        session.pop('account_name', None); session.pop('aws_access_key_id', None); session.pop('aws_secret_access_key', None)
    return jsonify({"success": True})

@app.route("/api/session", methods=["POST", "DELETE", "GET"])
@login_required
def aws_session():
    if request.method == "POST":
        name = request.json.get("name")
        account = next((k for k in load_keys(KEY_FILE) if k['name'] == name), None)
        if not account: return jsonify({"error": "账户未找到"}), 404
        session['account_name'], session['aws_access_key_id'], session['aws_secret_access_key'] = account['name'], account['access_key'], account['secret_key']
        return jsonify({"success": True, "name": account['name']})
    if request.method == "DELETE":
        session.pop('account_name', None); session.pop('aws_access_key_id', None); session.pop('aws_secret_access_key', None)
        return jsonify({"success": True})
    if 'account_name' in session: return jsonify({"logged_in": True, "name": session['account_name']})
    return jsonify({"logged_in": False})

@app.route("/api/regions")
@login_required
@aws_login_required
def get_regions():
    try:
        client = boto3.client('ec2', region_name='us-east-1', aws_access_key_id=g.aws_access_key_id, aws_secret_access_key=g.aws_secret_access_key, config=get_boto_config())
        response = client.describe_regions(AllRegions=True)
        regions = [{"code": r['RegionName'], "name": REGION_MAPPING.get(r['RegionName'], r['RegionName']), "enabled": r['OptInStatus'] in ['opt-in-not-required', 'opted-in']} for r in response['Regions']]
        return jsonify(sorted(regions, key=lambda x: x['name']))
    except Exception as e: return jsonify({"error": handle_aws_error(e)}), 500

@app.route("/api/instances")
@login_required
@aws_login_required
def get_instances():
    region = request.args.get("region")
    if not region: return jsonify({"error": "必须提供区域参数"}), 400
    instances = []
    try:
        ec2_client = boto3.client('ec2', region_name=region, aws_access_key_id=g.aws_access_key_id, aws_secret_access_key=g.aws_secret_access_key, config=get_boto_config())
        for r in ec2_client.describe_instances(Filters=[{'Name':'instance-state-name','Values':['pending','running','stopped']}])['Reservations']:
            for i in r['Instances']: instances.append({"type": "EC2", "region": region, "id": i['InstanceId'], "name": next((t['Value'] for t in i.get('Tags',[]) if t['Key'] == 'Name'), i['InstanceId']), "state": i['State']['Name'], "ip": i.get('PublicIpAddress', 'N/A')})
    except Exception as e: return jsonify({"error": handle_aws_error(e)}), 500
    return jsonify(instances)

@app.route("/api/instance-action", methods=["POST"])
@login_required
@aws_login_required
def instance_action():
    data = request.json
    action, region, instance_id, instance_type = data.get("action"), data.get("region"), data.get("instance_id"), data.get("instance_type")
    if not all([action, region, instance_id, instance_type]): return jsonify({"error": "缺少必要的操作参数"}), 400
    try:
        if instance_type == 'EC2':
            client = boto3.client('ec2', region_name=region, aws_access_key_id=g.aws_access_key_id, aws_secret_access_key=g.aws_secret_access_key, config=get_boto_config())
            if action == 'start': client.start_instances(InstanceIds=[instance_id])
            elif action == 'stop': client.stop_instances(InstanceIds=[instance_id])
            elif action == 'restart': client.reboot_instances(InstanceIds=[instance_id])
            elif action == 'delete': client.terminate_instances(InstanceIds=[instance_id])
        elif instance_type == 'Lightsail':
            client = boto3.client('lightsail', region_name=region, aws_access_key_id=g.aws_access_key_id, aws_secret_access_key=g.aws_secret_access_key, config=get_boto_config())
            if action == 'start': client.start_instance(instanceName=instance_id)
            elif action == 'stop': client.stop_instance(instanceName=instance_id)
            elif action == 'restart': client.reboot_instance(instanceName=instance_id)
            elif action == 'delete': client.delete_instance(instanceName=instance_id)
        return jsonify({"success": True, "message": f"实例 {instance_id} 的 {action} 请求已发送"})
    except Exception as e: return jsonify({"error": handle_aws_error(e)}), 500

@app.route("/api/ec2-instance-types")
@login_required
@aws_login_required
def get_ec2_instance_types():
    region = request.args.get("region")
    if not region: return jsonify({"error": "必须提供区域参数"}), 400
    try:
        client = boto3.client('ec2', region_name=region, aws_access_key_id=g.aws_access_key_id, aws_secret_access_key=g.aws_secret_access_key, config=get_boto_config())

        # 1. 先获取该区域可用的实例类型名称
        paginator_offerings = client.get_paginator('describe_instance_type_offerings')
        available_types = set()
        for page in paginator_offerings.paginate(LocationType='region', Filters=[{'Name': 'location', 'Values': [region]}]):
            for offering in page['InstanceTypeOfferings']:
                available_types.add(offering['InstanceType'])

        if not available_types:
            return jsonify([])

        # 2. 再根据名称列表批量获取详细信息
        paginator_types = client.get_paginator('describe_instance_types')
        detailed_types = []
        # AWS API一次最多查询100个类型
        available_types_list = list(available_types)
        for i in range(0, len(available_types_list), 100):
            chunk = available_types_list[i:i + 100]
            for page in paginator_types.paginate(InstanceTypes=chunk):
                for inst_type in page['InstanceTypes']:
                    vcpus = inst_type.get('VCpuInfo', {}).get('DefaultVCpus', '?')
                    memory_mib = inst_type.get('MemoryInfo', {}).get('SizeInMiB', 0)
                    memory_gib = round(memory_mib / 1024, 1) if memory_mib > 0 else 0

                    detailed_types.append({
                        "value": inst_type['InstanceType'],
                        "text": f"{inst_type['InstanceType']} ({vcpus}C / {memory_gib}G RAM)"
                    })

        sorted_types = sorted(detailed_types, key=lambda x: x['value'])

        # 将免费套餐提前
        for t_name in ['t3.micro', 't2.micro']:
            match = next((item for item in sorted_types if item['value'] == t_name), None)
            if match:
                sorted_types.insert(0, sorted_types.pop(sorted_types.index(match)))

        return jsonify(sorted_types)
    except Exception as e: 
        return jsonify({"error": handle_aws_error(e)}), 500
        
@app.route("/api/lightsail-bundles")
@login_required
@aws_login_required
def get_lightsail_bundles():
    region = request.args.get("region")
    if not region: return jsonify({"error": "必须提供区域参数"}), 400
    try:
        client = boto3.client('lightsail', region_name=region, aws_access_key_id=g.aws_access_key_id, aws_secret_access_key=g.aws_secret_access_key, config=get_boto_config())
        bundles = client.get_bundles()['bundles']
        formatted_bundles = [{"id": b['bundleId'], "name": f"{b['name']} ({b['ramSizeInGb']}GB RAM, {b['diskSizeInGb']}GB 磁盘, ${b['price']}/月)"} for b in bundles if b['isActive']]
        return jsonify(formatted_bundles)
    except Exception as e: return jsonify({"error": handle_aws_error(e)}), 500

@app.route("/api/query-quota", methods=["POST"])
@login_required
def query_quota():
    account_name = request.json.get("account_name")
    keys = load_keys(KEY_FILE)
    account = next((k for k in keys if k['name'] == account_name), None)
    if not account: return jsonify({"error": "账户未找到"}), 404
    try:
        client = boto3.client('service-quotas', region_name=QUOTA_REGION, aws_access_key_id=account['access_key'], aws_secret_access_key=account['secret_key'], config=get_boto_config())
        quota = client.get_service_quota(ServiceCode='ec2', QuotaCode=QUOTA_CODE)
        return jsonify({"quota": int(quota['Quota']['Value'])})
    except Exception as e: return jsonify({"error": handle_aws_error(e)})

@app.route("/api/instances/<service>", methods=["POST"])
@login_required
@aws_login_required
def start_create_instance(service):
    data = request.json
    instance_type = data.get("instance_type") if service == 'ec2' else data.get("bundle_id")
    task_id = f"{service}-{int(time.time())}"
    threading.Thread(target=create_instance_task, args=(service, task_id, g.aws_access_key_id, g.aws_secret_access_key, data["region"], instance_type, data["user_data"])).start()
    return jsonify({"success": True, "task_id": task_id})

@app.route("/api/activate-region", methods=["POST"])
@login_required
@aws_login_required
def start_activate_region():
    region = request.json.get("region")
    task_id = f"activate-{region}-{int(time.time())}"
    threading.Thread(target=activate_region_task, args=(task_id, g.aws_access_key_id, g.aws_secret_access_key, region)).start()
    return jsonify({"success": True, "task_id": task_id})

@app.route("/api/query-all-instances", methods=["POST"])
@login_required
@aws_login_required
def start_query_all():
    task_id = f"query-all-{int(time.time())}"
    threading.Thread(target=query_all_instances_task, args=(task_id, g.aws_access_key_id, g.aws_secret_access_key)).start()
    return jsonify({"success": True, "task_id": task_id})

@app.route("/api/task/<task_id>/logs")
@login_required
def get_task_logs(task_id):
    logs = []
    if task_id in task_logs:
        while not task_logs[task_id].empty(): logs.append(task_logs[task_id].get())
    return jsonify({"logs": logs})

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5001)