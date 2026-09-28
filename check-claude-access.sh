#!/bin/bash
# 检查当前 AWS 账号在指定区域有哪些 Claude 模型真正可用
#
# 用法:
#   export AWS_BEARER_TOKEN_BEDROCK=<Bedrock 长期 API 密钥>
#   REGION=us-east-1 ./check-claude-access.sh   # 不指定 REGION 默认 us-east-2
#
# 密钥获取: AWS 控制台 -> Amazon Bedrock -> API 密钥 -> 生成长期 API 密钥

REGION="${REGION:-us-east-2}"

if [ -z "$AWS_BEARER_TOKEN_BEDROCK" ]; then
  echo "请先设置密钥: export AWS_BEARER_TOKEN_BEDROCK=<你的 Bedrock 长期 API 密钥>"
  exit 1
fi

echo "正在查询 ${REGION} 区域的 Claude 模型..."
MODELS=$(curl -s -H "Authorization: Bearer $AWS_BEARER_TOKEN_BEDROCK" \
  "https://bedrock.${REGION}.amazonaws.com/foundation-models" \
  | python3 -c "import json,sys; print(' '.join(m['modelId'] for m in json.load(sys.stdin)['modelSummaries'] if 'anthropic' in m['modelId']))")

if [ -z "$MODELS" ]; then
  echo "该区域没有上架 Claude 模型，或密钥无效。"
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
