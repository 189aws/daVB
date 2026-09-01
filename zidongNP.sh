TG_TOKEN="8896559295:AAHuyFbUCYQedNRORneTN9sSu0Dc7lWyoFo"
CHAT_ID="1417748881"

sleep 60; \
echo -e "1\n2779\napi\n1" | sudo bash -c "$(curl -sL https://raw.githubusercontent.com/189aws/daVB/refs/heads/main/zhukong.sh)" -s -- -i | tee /tmp/np_output.log; \
MSG=$(awk '/API URL:|API KEY:|URI:/ {gsub(/^[ \t]+|[ \t]+$/, ""); print}' /tmp/np_output.log); \
if [ -n "$MSG" ]; then \
  curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    -d "text=$(echo -e "Np安装成功！\n\n$MSG")"; \
fi; rm -f /tmp/np_output.log
