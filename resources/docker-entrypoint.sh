#!/bin/bash


echo "Checking liquid env vars ..."
liquid_vars=(
  NODE_ENV
  LIQUID_URL
  LIQUID_TITLE
  CMD_HOST
  CMD_PORT
  CMD_DOMAIN
  CMD_PROTOCOL_USESSL
  CMD_ALLOW_ORIGIN
  CMD_USECDN
  CMD_EMAIL
  CMD_ALLOW_EMAIL_REGISTER
  CMD_ALLOW_ANONYMOUS
  CMD_ALLOW_ANONYMOUS_EDITS
  CMD_ALLOW_GRAVATAR
  CMD_ALLOW_FREEURL
  CMD_DB_URL
)
for name in "${liquid_vars[@]}"; do
  echo "checking $name"
  if [ -z "${!name}" ]; then
    echo "$name is empty, bailing"
    sleep 10
    exit 1
  fi
done
echo "liquid env vars good, starting up"


# Use gosu if the container started with root privileges
UID="$(id -u)"
[ "$UID" -eq 0 ] && GOSU="gosu codimd" || GOSU=""

if [ "$HMD_DB_URL" != "" ] && [ "$CMD_DB_URL" = "" ]; then
    CMD_DB_URL="$HMD_DB_URL"
fi

if [ "$HMD_IMAGE_UPLOAD_TYPE" != "" ] && [ "$CMD_IMAGE_UPLOAD_TYPE" = "" ]; then
    CMD_IMAGE_UPLOAD_TYPE="$HMD_IMAGE_UPLOAD_TYPE"
fi

DOCKER_SECRET_DB_URL_FILE_PATH="/run/secrets/dbURL"

if [ -f "$DOCKER_SECRET_DB_URL_FILE_PATH" ]; then
    CMD_DB_URL="$(cat $DOCKER_SECRET_DB_URL_FILE_PATH)"
fi

if [ "$CMD_DB_URL" = "" ]; then
    CMD_DB_URL="postgres://hackmd:hackmdpass@hackmdPostgres:5432/hackmd"
fi

export CMD_DB_URL

DB_SOCKET=$(echo ${CMD_DB_URL} | sed -e 's/.*:\/\//\/\//' -e 's/.*\/\/[^@]*@//' -e 's/\/.*$//')

if [ "$DB_SOCKET" != "" ]; then
    dockerize -wait "tcp://${DB_SOCKET}" -timeout 30s
fi

$GOSU ./node_modules/.bin/sequelize db:migrate

# Print warning if local data storage is used but no volume is mounted
[ "$CMD_IMAGE_UPLOAD_TYPE" = "filesystem" ] && { mountpoint -q ./public/uploads || {
    echo "
        #################################################################
        ###                                                           ###
        ###                        !!!WARNING!!!                      ###
        ###                                                           ###
        ###        Using local uploads without persistence is         ###
        ###            dangerous. You'll loose your data on           ###
        ###              container removal. Check out:                ###
        ###  https://docs.docker.com/engine/tutorials/dockervolumes/  ###
        ###                                                           ###
        ###                       !!!WARNING!!!                       ###
        ###                                                           ###
        #################################################################
    ";
} ; }

# Change owner and permission if filesystem backend is used and user has root permissions
if [ "$UID" -eq 0 ] && [ "$CMD_IMAGE_UPLOAD_TYPE" = "filesystem" ]; then
    if [ "$UID" -eq 0 ]; then
        chown -R codimd ./public/uploads
        chmod 700 ./public/uploads
    else
        echo "
            #################################################################
            ###                                                           ###
            ###                        !!!WARNING!!!                      ###
            ###                                                           ###
            ###        Container was started without root permissions     ###
            ###           and filesystem storage is being used.           ###
            ###        In case of filesystem errors these need to be      ###
            ###                      changed manually                     ###
            ###                                                           ###
            ###                       !!!WARNING!!!                       ###
            ###                                                           ###
            #################################################################
        ";
    fi
fi

# Sleep to make sure everything is fine...
sleep 3

# run
exec $GOSU "$@"
