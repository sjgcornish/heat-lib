#!/bin/bash 
trap 'echo "Failed" > $heat_outputs_path.status; exit;' ERR

if [ "$http_proxy" = "none" ]; then
  unset http_proxy
else
  export HTTP_PROXY=$http_proxy
fi

if [ "$https_proxy" = "none" ]; then
  unset https_proxy
else
  export HTTPS_PROXY=$https_proxy
fi

curl --silent --location $rpm_link -o /tmp/rstudio.rpm

yum -y install R

yum -y install /tmp/rstudio.rpm 

yum -y install openssl098e

chkconfig rstudio-server on
# Insert Script Here
echo "Success" > $heat_outputs_path.status
