#!/bin/bash
echo "VLESS + REALITY (оптимизировано под МТС)"
sleep 2

apt update
apt install qrencode curl jq -y

# BBR
if sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
echo "bbr уже включен"
else
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p
fi

# Установка Xray
bash -c "$(curl -4 -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

rm -f /usr/local/etc/xray/.keys

UUID=$(xray uuid)
KEYS=$(xray x25519)
PRIVATE=$(echo "$KEYS" | grep PrivateKey | awk '{print $2}')
PUBLIC=$(echo "$KEYS" | grep PublicKey | awk '{print $2}')
SID=$(openssl rand -hex 8)

cat << EOF > /usr/local/etc/xray/.keys
uuid: $UUID
PrivateKey: $PRIVATE
PublicKey: $PUBLIC
shortsid: $SID
EOF

# CONFIG
cat << EOF > /usr/local/etc/xray/config.json
{
"log":{"loglevel":"warning"},
"inbounds":[
{
"port":443,
"protocol":"vless",
"settings":{
"clients":[{"email":"main","id":"$UUID","flow":"xtls-rprx-vision"}],
"decryption":"none"
},
"streamSettings":{
"network":"tcp",
"security":"reality",
"realitySettings":{
"show":false,
"dest":"www.microsoft.com:443",
"serverNames":["www.microsoft.com"],
"privateKey":"$PRIVATE",
"shortIds":["$SID"]
}
}
}
],
"outbounds":[{"protocol":"freedom"}]
}
EOF

# MAINUSER
cat << 'EOF' > /usr/local/bin/mainuser
#!/bin/bash
uuid=$(cat /usr/local/etc/xray/.keys | grep uuid | awk '{print $2}')
pbk=$(cat /usr/local/etc/xray/.keys | grep PublicKey | awk '{print $2}')
sid=$(cat /usr/local/etc/xray/.keys | grep shortsid | awk '{print $2}')
ip=$(curl -4 -s icanhazip.com)

link="vless://$uuid@$ip:443?security=reality&sni=www.microsoft.com&fp=chrome&pbk=$pbk&sid=$sid&type=tcp&flow=xtls-rprx-vision#main"

echo ""
echo "===== ОСНОВНОЙ ПОЛЬЗОВАТЕЛЬ ====="
echo ""
echo "Ссылка:"
echo "$link"

echo ""
echo "QR-код:"
echo "$link" | qrencode -t ansiutf8
EOF
chmod +x /usr/local/bin/mainuser

# NEWUSER
cat << 'EOF' > /usr/local/bin/newuser
#!/bin/bash
read -p "Введите имя пользователя: " email

if [[ -z "$email" || "$email" == *" "* ]]; then
echo "Ошибка имени"
exit 1
fi

uuid=$(xray uuid)

jq --arg email "$email" --arg uuid "$uuid" \
'.inbounds[0].settings.clients += [{"email":$email,"id":$uuid,"flow":"xtls-rprx-vision"}]' \
/usr/local/etc/xray/config.json > tmp && mv tmp /usr/local/etc/xray/config.json

systemctl restart xray

pbk=$(cat /usr/local/etc/xray/.keys | grep PublicKey | awk '{print $2}')
sid=$(cat /usr/local/etc/xray/.keys | grep shortsid | awk '{print $2}')
ip=$(curl -4 -s icanhazip.com)

link="vless://$uuid@$ip:443?security=reality&sni=www.microsoft.com&fp=chrome&pbk=$pbk&sid=$sid&type=tcp&flow=xtls-rprx-vision#$email"

echo ""
echo "Ссылка:"
echo "$link"

echo ""
echo "QR-код:"
echo "$link" | qrencode -t ansiutf8
EOF
chmod +x /usr/local/bin/newuser

# USERLIST
cat << 'EOF' > /usr/local/bin/userlist
#!/bin/bash
echo "Список пользователей:"
jq -r '.inbounds[0].settings.clients[].email' /usr/local/etc/xray/config.json
EOF
chmod +x /usr/local/bin/userlist

# RMUSER
cat << 'EOF' > /usr/local/bin/rmuser
#!/bin/bash
emails=($(jq -r '.inbounds[0].settings.clients[].email' "/usr/local/etc/xray/config.json"))

for i in "${!emails[@]}"; do
echo "$((i+1)). ${emails[$i]}"
done

read -p "Номер пользователя: " num
selected="${emails[$((num-1))]}"

jq --arg email "$selected" \
'(.inbounds[0].settings.clients) |= map(select(.email != $email))' \
/usr/local/etc/xray/config.json > tmp && mv tmp /usr/local/etc/xray/config.json

systemctl restart xray

echo "Удален: $selected"
EOF
chmod +x /usr/local/bin/rmuser

# HELP
cat << 'EOF' > ~/help
Команды:

mainuser  - показать основную ссылку
newuser   - добавить пользователя
rmuser    - удалить пользователя
userlist  - список пользователей

перезапуск:
systemctl restart xray
EOF

systemctl restart xray

echo ""
echo "===== УСТАНОВКА ЗАВЕРШЕНА ====="
mainuser
