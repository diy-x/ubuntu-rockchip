# shellcheck shell=bash
function install-mongodb(){
    local rootfs="$1"
    local overlay="$2"
    echo "install mongodb with rootfs:${rootfs} overlay:${overlay}"

    chroot "${rootfs}" bash -c "curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/mongodb-server-7.0.gpg"

    cat <<-EOF >"${rootfs}/etc/apt/sources.list.d/mongodb-org-7.0.list"
    deb [ arch=amd64,arm64 signed-by=/etc/apt/trusted.gpg.d/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse
EOF
    chroot "${rootfs}" sudo apt-get update
    chroot "${rootfs}" apt-get  install -y mongodb-org

    chroot "${rootfs}" mongod --dbpath /var/lib/mongodb --fork --logpath /var/log/mongodb.log
    chroot "${rootfs}" sleep 5
    chroot "${rootfs}" mongosh admin --eval 'db.createUser({user:"nts", pwd:"nts##", roles:[{role:"readWriteAnyDatabase", db:"admin"}]})'
    chroot "${rootfs}" mongod --dbpath /var/lib/mongodb --shutdown
    chroot "${rootfs}" printf 'security:\n  authorization: enabled\n' >> /etc/mongod.conf
    # fix mongodb service reated permition
    chroot "${rootfs}" chown -R mongodb:mongodb /var/lib/mongodb
    chroot "${rootfs}" chmod -R 755 /var/lib/mongodb
    chroot "${rootfs}" chown -R mongodb:mongodb /var/log/mongodb.log
    chroot "${rootfs}" chmod -R 755 /var/log/mongodb.log


    return 0
}
