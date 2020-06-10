# Generate temporary self-signed certificates
openssl req -nodes -new -x509 \
  -keyout /etc/ssl/${jitsi_hostname}.key \
  -out /etc/ssl/${jitsi_hostname}.crt \
  -subj "/C=NL/ST=ZH/O=Q42/CN=${jitsi_hostname}"

# Prepare configuration
apt-get install -y debconf-utils
cat << EOF | sudo debconf-set-selections
jitsi-videobridge	    jitsi-videobridge/jvb-hostname    string ${jitsi_hostname}
jitsi-meet            jitsi-meet/jvb-serve              boolean false
jitsi-meet-prosody    jitsi-videobridge/jvb-hostname    string ${jitsi_hostname}
jitsi-meet-prosody    jitsi-videobridge/jvbsecret       password ${jitsi_jvbsecret}
jitsi-meet-web-config jitsi-meet/cert-choice            select I want to use my own certificate
jitsi-meet-web-config jitsi-meet/cert-path-crt          string /etc/ssl/${jitsi_hostname}.crt
jitsi-meet-web-config jitsi-meet/cert-path-key          string /etc/ssl/${jitsi_hostname}.key
EOF

# Package repos
apt-get install -y apt-transport-https ca-certificates

## Jitsi
curl https://download.jitsi.org/jitsi-key.gpg.key | apt-key add -
sh -c "echo 'deb https://download.jitsi.org stable/' > /etc/apt/sources.list.d/jitsi-stable.list"

## Google Cloud Platform
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -

## Update
apt-get -y update
export DEBIAN_FRONTEND=noninteractive

## Then... do something specific
