#!/bin/sh -xe

WAIT_APPROVED_SEC=${WAIT_APPROVED_SEC:-600}                                                                        

SHARED="/srv/nuvlaedge/shared"
SYNC_FILE=".tls"
CA="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
USER="nuvla"

# We gotta get the namespace...

echo "The NuvlaEdge UUID is set to: ${NUVLAEDGE_UUID}"

echo "The MY_NAMESPACE is set to: ${MY_NAMESPACE}"

env

if [ ! -z $SET_MULTIPLE ]
then
    echo "We are in the multiple NE mode..."
fi

if [ ! -z $NUVLAEDGE_UUID ]
then
    NAMESPACE=$(echo $NUVLAEDGE_UUID | awk -F "/" '{print $2}')
    if [ -z $NAMESPACE ]
    then
        NAMESPACE=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 6; echo)
    fi
fi
echo "namespace string got set to: ${NAMESPACE}"

# probably not a good idea to be random?
SYNC_FILE=".${NAMESPACE}.tls"
echo $SYNC_FILE

## exit 1

RND_EXT=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 6; echo)                                                  

NE_CSR=${USER}-csr-${NAMESPACE}                                                                            
# CSR_NAME=${CSR_NAME:-${NE_CSR}}
# maybe the CSR name should come from an ENV variable?
# this could be 
CSR_NAME=${NE_CSR:-"nulvaedge-csr"}
echo "nuvla CSR set to ${CSR_NAME}"      

CRB_NAME=${USER}-crb-${NAMESPACE}

is_cred_valid() {
  CRED_PATH=${1}

  echo "INFO: md5 of certificate:"
  openssl x509 -noout -modulus -in ${CRED_PATH}/cert.pem | openssl md5
  echo "INFO: md5 of private key:"
  openssl rsa -noout -modulus -in ${CRED_PATH}/key.pem | openssl md5

  curl -f https://${KUBERNETES_SERVICE_HOST}/api \
    --cacert ${CRED_PATH}/ca.pem \
    --cert ${CRED_PATH}/cert.pem  \
    --key ${CRED_PATH}/key.pem
  if [ $? -ne 0 ]
  then
    return 1
  else
    return 0
  fi
}

generate_credentials() {
  echo "INFO: Generating new user '${USER}' and API access certificates."

  openssl genrsa -out key.pem 4096

  cat>nuvlaedge.cnf <<EOF
[ req ]
default_bits = 4096
prompt = no
default_md = sha256
distinguished_name = dn
[ dn ]
CN = ${USER}
O = sixsq
[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth,clientAuth
EOF

  openssl req -config ./nuvlaedge.cnf -new -key key.pem -out nuvlaedge.csr

  BASE64_CSR=$(cat ./nuvlaedge.csr | base64 | tr -d '\n')

  cat>nuvlaedge-csr.yaml <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${CSR_NAME}
  labels:
    nuvlaedge.component: "True"
    nuvlaedge.deployment: "production"
spec:
  groups:
  - system:authenticated
  request: ${BASE64_CSR}
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - digital signature
  - key encipherment
  - client auth
EOF

  kubectl delete -f nuvlaedge-csr.yaml || true

  kubectl apply -f nuvlaedge-csr.yaml

  kubectl get csr

  timeout ${WAIT_APPROVED_SEC} sh -c 'while [[ -z "$CERT" ]]
do
CERT=`kubectl get csr ${CSR_NAME} -o jsonpath="{.status.certificate}" | base64 -d`
done'
  kubectl get csr ${CSR_NAME} -o jsonpath="{.status.certificate}" | base64 -d > cert.pem

  echo "INFO: Validating credentials."

  if is_cred_valid .
  then
    cp ca.pem cert.pem key.pem ${SHARED}
    echo `date +%s` > ${SHARED}/${SYNC_FILE}
    echo "INFO: Success. Generated new valid credentials: \n$(ls -al ${SHARED}/*.pem ${SHARED}/${SYNC_FILE})"
  else
    echo "ERROR: Generated credentials are not valid."
    return 1
  fi

  echo "INFO: Assigning cluster-admin privileges to user '${USER}'."

  cat>nuvla-cluster-role-binding.yaml <<EOF
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
 name: ${CRB_NAME}
 labels:
    nuvlaedge.component: "True"
    nuvlaedge.deployment: "production"
subjects:
- kind: User
  name: ${USER}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF

  kubectl apply -f nuvla-cluster-role-binding.yaml
}

############

if [ ! -f ${CA} ]
then
  echo "ERROR: Cannot find CA certificate at ${CA}. Make sure a proper Service Account is being used for running the container.."
  exit 1
else
  cp ${CA} ca.pem
fi

if [ ! -f ${SHARED}/${SYNC_FILE} ]
then
  echo "INFO: Sync file ${SHARED}/${SYNC_FILE} is not available. Generating new credentials."
  generate_credentials
else
  if is_cred_valid ${SHARED}
  then
    echo "INFO: Reusing existing certificates from ${SHARED}: \n$(ls -l ${SHARED}/*.pem)"
  else
    echo "ERROR: Existing certificates are not valid. Generating new ones."
    rm -f ${SHARED}/${SYNC_FILE} ${SHARED}/{ca,cert,key}.pem
    generate_credentials
  fi
fi