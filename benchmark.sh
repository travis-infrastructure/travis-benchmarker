#!/bin/bash

make_multipart() {
  label="$1"
  read -r -d '' HEADER <<- EOF
Content-Type: multipart/mixed; boundary="MIMEBOUNDARY"
MIME-Version: 1.0
--MIMEBOUNDARY
Content-Disposition: attachment; filename="cloud-config"
Content-Transfer-Encoding: 7bit
Content-Type: text/cloud-config
Mime-Version: 1.0
#cloud-config
# vim:filetype=yaml
EOF

  read -r -d '' BOUNDARY <<EOF
--MIMEBOUNDARY
Content-Disposition: attachment; filename="cloud-init"
Content-Transfer-Encoding: 7bit
Content-Type: text/x-shellscript
Mime-Version: 1.0
EOF

  read -r -d '' FOOTER <<EOF
--MIMEBOUNDARY--
EOF

  echo "$HEADER" > "${label}/${label}.multipart"
  cat "${label}/cloud-config.yml" >> "${label}/${label}.multipart"
  echo "$BOUNDARY" >> "${label}/${label}.multipart"
  cat "${label}/cloud-init.sh" >> "${label}/${label}.multipart"
  echo "$FOOTER" >> "${label}/${label}.multipart"

  gzip -f "${label}/${label}.multipart"
}

make_token() {
  cat /proc/sys/kernel/random/uuid
}

run_instances() {
  label="$1"
  echo aws ec2 run-instances \
  --region us-east-1 \
  --key-name aj \
  --image-id ami-a43c8dde \
  --instance-type c3.2xlarge \
  --security-group-ids "sg-4e80c734" "sg-4d80c737" \
  --subnet-id subnet-addd3791 \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=role,Value=aj-test}]' \
  --client-token "$make_token" \
  --user-data "fileb://${label}/user-data.${label}.multipart.gz" \
  --block-device-mappings 'DeviceName=/dev/sda1,VirtualName=/dev/xvdc,Ebs={DeleteOnTermination=true,SnapshotId=snap-05ddc125d72e3592d,VolumeSize=8,VolumeType=gp2}'
}

die() {
  echo "$@" && exit 1
}

main() {
  label="$1"
  [ -z "$label" ] && die "Please provide a label for this test, corresponding to a directory containing LABEL/cloud-init.sh and LABEL/cloud-config.yml."
  [ ! -d "$label" ] && die "Directory $label not found."

  make_multipart "$label"
  run_instances "$label"
}

main "$@"
