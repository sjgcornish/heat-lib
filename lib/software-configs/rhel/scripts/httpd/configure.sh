#!/bin/bash 
trap 'echo "Failed" > $heat_outputs_path.status; exit;' ERR

function generate_conf_file {
cat > /tmp/ssl.conf << EOF
Listen 443 https
SSLPassPhraseDialog exec:/usr/libexec/httpd-ssl-pass-dialog
SSLSessionCache         shmcb:/run/httpd/sslcache(512000)
SSLSessionCacheTimeout  300
SSLRandomSeed startup file:/dev/urandom  256
SSLRandomSeed connect builtin 
SSLCryptoDevice builtin

<VirtualHost _default_:443>

ErrorLog logs/ssl_error_log
TransferLog logs/ssl_access_log
LogLevel warn

SSLEngine on
SSLProtocol all -SSLv2
SSLCipherSuite HIGH:MEDIUM:!aNULL:!MD5:!SEED:!IDEA
SSLCertificateFile /etc/pki/tls/certs/localhost.crt
SSLCertificateKeyFile /etc/pki/tls/private/localhost.key
#SSLCACertificateFile /etc/pki/tls/certs/ca-bundle.crt
<Files ~ "\.(cgi|shtml|phtml|php3?)$">
SSLOptions +StdEnvVars
</Files>
<Directory "/var/www/cgi-bin">
SSLOptions +StdEnvVars
</Directory>

BrowserMatch "MSIE [2-5]" nokeepalive ssl-unclean-shutdown downgrade-1.0 force-response-1.0

CustomLog logs/ssl_request_log "%t %h %{SSL_PROTOCOL}x %{SSL_CIPHER}x \"%r\" %b"

</VirtualHost>
EOF
}

# TODO add hostname support for ssl 

#########################
### SSL Configuration ###
#########################
if [ $ssl_config_type = "none" ]; then 
  rm -f /etc/httpd/conf.d/ssl.conf
  systemctl restart httpd.service
  echo "Success" > $heat_outputs_path.status
  exit
elif [ $ssl_config_type = "provided" ]; then 
  if [ $ssl_cert = "none" ] || [ $ssl_key = "none" ] ; then 
    >&2 echo "If ssl_config_type is set to provided, the ssl_cert and ssl_key attributes must be passed" 
    (exit 1) 
  fi 

  # Create temp files for validation
  echo $ssl_cert | base64 -d  > /tmp/ssl.cert
  echo $ssl_key | base64 -d > /tmp/ssl.key

  # Verify key matches cert
  # TODO add verification for CA file
  match=`( openssl x509 -noout -modulus -in /tmp/ssl.cert | openssl md5 ; openssl rsa -noout -modulus -in /tmp/ssl.key | openssl md5 ) | uniq | wc -l`
  if [ $match != 1 ]; then
    >&2 echo "Provided SSL certificate does not match provided SSL key"
    (exit 1) 
  fi 

  generate_conf_file

  # Gather lines from ssl.conf to be replaced
  ssl_conf_file="/tmp/ssl.conf"
  ssl_cert_line=`grep SSLCertificateFile $ssl_conf_file`
  ssl_key_line=`grep SSLCertificateKeyFile $ssl_conf_file`
  ssl_ca_line=`grep SSLCACertificateFile $ssl_conf_file`

  # Replace files 
  ssl_directory="/etc/httpd/ssl"
  mkdir -p $ssl_directory 
  mv /tmp/ssl.cert $ssl_directory/
  mv /tmp/ssl.key $ssl_directory/
  if [ $ssl_ca != "none" ]; then 
    echo $ssl_ca | base64 -d > $ssl_directory/ssl.ca
  fi

  # Adjust ssl.conf
  sed -i "s~$ssl_cert_line~SSLCertificateFile $ssl_directory/ssl.cert~g" $ssl_conf_file
  sed -i "s~$ssl_key_line~SSLCertificateKeyFile $ssl_directory/ssl.key~g" $ssl_conf_file
  if [ $ssl_ca != "none" ]; then 
    sed -i "s~$ssl_ca_line~SSLCACertificateFile $ssl_directory/ssl.ca~g" $ssl_conf_file
  fi

  # Move conf file in place 
  mv $ssl_conf_file /etc/httpd/conf.d
  
  # Restart service 
  systemctl restart httpd.service
elif [ $ssl_config_type = "generated" ]; then
  #TODO
  break
fi

############################
### Reverse Proxy Enable ###
############################
cat > /etc/httpd/conf.d/enable_proxy.html << EOF
SSLProxyEngine on
ProxyRequests Off
EOF

echo "Success" > $heat_outputs_path.status
