#!/bin/bash
# 检查当前 AWS 账号在指定区域有哪些 Claude 模型真正可用
#
# 用法:
#   export AWS_BEARER_TOKEN_BEDROCK=<Bedrock 长期 API 密钥>
#   REGION=us-east-1 ./check-claude-access.sh   # 不指定 REGION 默认 us-east-2
#
# 密钥获取: AWS 控制台 -> Amazon Bedrock -> API 密钥 -> 生成长期 API 密钥
#
# 原理:
#   1. 先调 ListInferenceProfiles 拿权威推理配置 ID(最可靠, 不靠猜);
#   2. 再调 ListFoundationModels 拿基础模型列表, 对每个试"直接调用"和"global.启发式";
#   3. 逐个用 Converse API 实测, 以 HTTP 200 为准。

SCRIPT_VERSION="2026-09-28-v7"

REGION="${REGION:-us-east-2}"

if [ -z "$AWS_BEARER_TOKEN_BEDROCK" ]; then
  echo "请先设置密钥: export AWS_BEARER_TOKEN_BEDROCK=<你的 Bedrock 长期 API 密钥>"
  exit 1
fi

AUTH_HEADER="Authorization: Bearer $AWS_BEARER_TOKEN_BEDROCK"

echo "check-claude-access.sh $SCRIPT_VERSION"

test_model() {
  local id="$1" enc="$1"
  if [[ "$id" == *"/"* ]]; then
    enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$id")
  fi
  curl -s -o /dev/null -w "%{http_code}" --max-time 20 -X POST \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d '{"messages":[{"role":"user","content":[{"text":"hi"}]}]}' \
    "https://bedrock-runtime.${REGION}.amazonaws.com/model/${enc}/converse"
}

echo "正在查询 ${REGION} 区域的推理配置..."
P_RESP=$(mktemp)
P_CODE=$(curl -s -o "$P_RESP" -w "%{http_code}" --max-time 20 -H "$AUTH_HEADER" \
  "https://bedrock.${REGION}.amazonaws.com/inference-profiles?maxResults=1000")

PROFILES=""
if [ "$P_CODE" = "200" ]; then
  PROFILES=$(P_RESP="$P_RESP" python3 -c "
import json, os, re
raw = open(os.environ['P_RESP']).read()
try:
    data = json.loads(raw)
except Exception:
    data = {}
ids = []
if isinstance(data, dict):
    for key in ('inferenceProfileSummaries', 'inferenceProfiles', 'profiles', 'items'):
        items = data.get(key)
        if isinstance(items, list):
            for p in items:
                if not isinstance(p, dict):
                    continue
                for f in ('inferenceProfileId',):
                    v = p.get(f)
                    if v and 'anthropic' in str(v).lower():
                        ids.append(str(v).strip())
ids += re.findall(r'global\.anthropic\.[A-Za-z0-9_.:-]+', raw)
seen = set(); out = []
for i in ids:
    if i not in seen:
        seen.add(i); out.append(i)
print(chr(10).join(out))
")
  echo "找到 $(echo "$PROFILES" | grep -c . 2>/dev/null || echo 0) 个 Claude 推理配置。"
else
  echo "推理配置列表查询失败(HTTP ${P_CODE:-无响应})，将跳过该项。"
fi
rm -f "$P_RESP"

echo "正在查询 ${REGION} 区域的基础模型..."
LIST_RESP=$(mktemp)
LIST_CODE=$(curl -s -o "$LIST_RESP" -w "%{http_code}" --max-time 20 -H "$AUTH_HEADER" \
  "https://bedrock.${REGION}.amazonaws.com/foundation-models")

if [ "$LIST_CODE" != "200" ]; then
  echo "模型列表查询失败，HTTP 状态码: ${LIST_CODE:-无响应}"
  echo "返回内容:"
  head -c 500 "$LIST_RESP"; echo
  rm -f "$LIST_RESP"
  echo ""
  echo "排查: 401 = 密钥无效;"
  echo "      403 且返回中含 explicit deny in a service control policy = 被组织 SCP 策略禁止(常见于限制可用区域), 需联系 AWS 管理员修改策略;"
  echo "      403 其他 = 密钥无权限或已被撤销，请去 Bedrock 控制台检查;"
  echo "      无响应/000 = 网络波动，重试一次即可。"
  exit 1
fi

MODELS=$(LIST_RESP="$LIST_RESP" python3 -c "
import json, os
data = json.load(open(os.environ['LIST_RESP']))
ids = [m['modelId'] for m in data.get('modelSummaries', []) if 'anthropic' in m['modelId']]
print(' '.join(ids))
")
rm -f "$LIST_RESP"

if [ -z "$MODELS" ] && [ -z "$PROFILES" ]; then
  echo "该区域没有上架 Claude 模型。"
  exit 1
fi

# 预检: 账号是否提交了 Anthropic 模型使用案例表(未提交时所有 Claude 调用都会被拒)
FIRST_MODEL=$(echo "$MODELS" | awk '{print $1}')
if [ -n "$FIRST_MODEL" ]; then
  PROBE_RESP=$(mktemp)
  curl -s -o "$PROBE_RESP" --max-time 20 -X POST \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d '{"messages":[{"role":"user","content":[{"text":"hi"}]}]}' \
    "https://bedrock-runtime.${REGION}.amazonaws.com/model/global.${FIRST_MODEL}/converse" || true
  if grep -qi "use case details" "$PROBE_RESP" 2>/dev/null; then
    echo ""
    echo "⚠️  此账号尚未提交 Anthropic 模型使用案例表，所有 Claude 模型暂时无法调用。"
    echo "   请前往 Bedrock 控制台 → 模型访问 → 提交 Anthropic 使用案例表，约 15 分钟后重跑本脚本。"
    rm -f "$PROBE_RESP"
    exit 1
  fi
  rm -f "$PROBE_RESP"
fi

USABLE=""

echo ""
echo "=== 权威推理配置实测 (ListInferenceProfiles) ==="
if [ -z "$PROFILES" ]; then
  echo "(无)"
else
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    code=$(test_model "$p")
    if [ "$code" = "200" ]; then status="✅ 可用"; USABLE="$USABLE $p"; else status="❌ ($code)"; fi
    printf "%-60s %s\n" "$p" "$status"
  done <<< "$PROFILES"
fi

echo ""
echo "=== 基础模型实测 (直接调用 / global.启发式) ==="
printf "%-50s %-8s %-8s %s\n" "模型 ID" "直接" "启发式" "结论"
echo "------------------------------------------------------------------------------------------"
for m in $MODELS; do
  c1=$(test_model "$m")
  c2=$(test_model "global.$m")
  if [ "$c1" = "200" ] || [ "$c2" = "200" ]; then
    status="✅ 可用"
    [ "$c1" = "200" ] && USABLE="$USABLE $m"
    [ "$c2" = "200" ] && USABLE="$USABLE global.$m"
  else
    status="❌ 无权限"
  fi
  printf "%-50s %-10s %-10s %s\n" "$m" "$c1" "$c2" "$status"
done

USABLE=$(echo "$USABLE" | tr ' ' '\n' | awk 'NF && !seen[$0]++' | tr '\n' ' ')

echo ""
echo "=== 当前可用的 Claude 调用 ID ==="
if [ -z "$USABLE" ]; then
  echo "(无)"
else
  for u in $USABLE; do echo "  $u"; done
fi
echo ""
echo "判读: 200=能用; 403=账号无权限(需联系 AWS Sales 开通); 404=该 ID 不存在(目录调整中, 可过段时间重查);"
echo "      400(直接调用列)=新模型必须走推理配置, 属正常, 看其他列即可。"
