#!/bin/bash
# 检查当前 AWS 账号在指定区域有哪些 Claude 模型真正可用
#
# 用法:
#   export AWS_BEARER_TOKEN_BEDROCK=<Bedrock 长期 API 密钥>
#   REGION=us-east-1 ./check-claude-access.sh   # 不指定 REGION 默认 us-east-2
#
# 密钥获取: AWS 控制台 -> Amazon Bedrock -> API 密钥 -> 生成长期 API 密钥

SCRIPT_VERSION="2026-09-28-v4"

REGION="${REGION:-us-east-2}"

if [ -z "$AWS_BEARER_TOKEN_BEDROCK" ]; then
  echo "请先设置密钥: export AWS_BEARER_TOKEN_BEDROCK=<你的 Bedrock 长期 API 密钥>"
  exit 1
fi

echo "check-claude-access.sh $SCRIPT_VERSION"
echo "正在查询 ${REGION} 区域的 Claude 模型..."
LIST_RESP=$(mktemp)
LIST_CODE=$(curl -s -o "$LIST_RESP" -w "%{http_code}" -H "Authorization: Bearer $AWS_BEARER_TOKEN_BEDROCK" \
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

if [ -z "$MODELS" ]; then
  echo "该区域没有上架 Claude 模型。"
  exit 1
fi

test_model() {
  curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "Authorization: Bearer $AWS_BEARER_TOKEN_BEDROCK" \
    -H "Content-Type: application/json" \
    -d '{"messages":[{"role":"user","content":[{"text":"hi"}]}]}' \
    "https://bedrock-runtime.${REGION}.amazonaws.com/model/$1/converse"
}

printf "\n%-50s %-10s %-10s %s\n" "模型 ID" "直接调用" "推理配置" "结论"
echo "------------------------------------------------------------------------------------------"
for m in $MODELS; do
  c1=$(test_model "$m")
  c2=$(test_model "global.$m")
  if [ "$c1" = "200" ] || [ "$c2" = "200" ]; then
    status="✅ 可用"
  else
    status="❌ 无权限"
  fi
  printf "%-50s %-10s %-10s %s\n" "$m" "$c1" "$c2" "$status"
done

echo ""
echo "判读: 200=能用; 403=账号无权限(需联系 AWS Sales 开通);"
echo "      直接调用失败但推理配置 200 = 有权限, 使用时模型 ID 必须加 global. 前缀。"
