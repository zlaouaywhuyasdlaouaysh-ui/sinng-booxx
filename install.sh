#!/bin/bash

author=233boy
# github=https://github.com/233boy/sing-box

# bash fonts colors
red='\e[31m'
yellow='\e[33m'
gray='\e[90m'
green='\e[92m'
blue='\e[94m'
magenta='\e[95m'
cyan='\e[96m'
none='\e[0m'
_red() { echo -e ${red}$@${none}; }
_blue() { echo -e ${blue}$@${none}; }
_cyan() { echo -e ${cyan}$@${none}; }
_green() { echo -e ${green}$@${none}; }
_yellow() { echo -e ${yellow}$@${none}; }
_magenta() { echo -e ${magenta}$@${none}; }
_red_bg() { echo -e "\e[41m$@${none}"; }

is_err=$(_red_bg 错误!)
is_warn=$(_red_bg 警告!)

err() {
    echo -e "\n$is_err $@\n" && exit 1
}

warn() {
    echo -e "\n$is_warn $@\n"
}

# root
[[ $EUID != 0 ]] && err "当前非 ${yellow}ROOT用户.${none}"

# apt-get, yum, zypper or apk
cmd=$(type -P apt-get || type -P yum || type -P zypper || type -P apk)
[[ ! $cmd ]] && err "此脚本仅支持 ${yellow}(Ubuntu or Debian or CentOS or SUSE or Alpine)${none}."

# systemd or openrc
is_systemd=$(type -P systemctl)
is_openrc=$(type -P rc-service)
[[ ! $is_systemd && ! $is_openrc ]] && {
    err "此系统缺少 ${yellow}(systemctl 或 rc-service)${none}, 请安装 systemd 或确认 OpenRC 已启用."
}

# wget installed or none
is_wget=$(type -P wget)

# x64
case $(uname -m) in
amd64 | x86_64)
    is_arch=amd64
    ;;
*aarch64* | *armv8*)
    is_arch=arm64
    ;;
*)
    err "此脚本仅支持 64 位系统..."
    ;;
esac

is_core=sing-box
is_core_name=sing-box
is_core_dir=/etc/$is_core
is_core_bin=$is_core_dir/bin/$is_core
is_core_repo=SagerNet/$is_core
is_conf_dir=$is_core_dir/conf
is_log_dir=/var/log/$is_core
is_sh_bin=/usr/local/bin/$is_core
is_sh_dir=$is_core_dir/sh
is_sh_repo=$author/$is_core
is_pkg="wget tar bash openssl python3"
# Alpine: gcompat provides glibc compatibility for prebuilt binaries
[[ $cmd =~ apk ]] && is_pkg="$is_pkg gcompat jq"
is_config_json=$is_core_dir/config.json
tmp_var_lists=(
    tmpcore
    tmpsh
    tmpjq
    is_core_ok
    is_sh_ok
    is_jq_ok
    is_pkg_ok
)

# tmp dir
tmpdir=$(mktemp -u)
[[ ! $tmpdir ]] && {
    tmpdir=/tmp/tmp-$RANDOM
}

# set up var
for i in ${tmp_var_lists[*]}; do
    export $i=$tmpdir/$i
done

# load bash script.
load() {
    . $is_sh_dir/src/$1
}

# wget add --no-check-certificate
_wget() {
    [[ $proxy ]] && export https_proxy=$proxy
    wget --no-check-certificate $*
}

# print a mesage
msg() {
    case $1 in
    warn)
        local color=$yellow
        ;;
    err)
        local color=$red
        ;;
    ok)
        local color=$green
        ;;
    esac

    echo -e "${color}$(date +'%T')${none}) ${2}"
}

# show help msg
show_help() {
    echo -e "Usage: $0 [-f xxx | -l | -p xxx | -v xxx | -h]"
    echo -e "  -f, --core-file <path>          自定义 $is_core_name 文件路径, e.g., -f /root/$is_core-linux-amd64.tar.gz"
    echo -e "  -l, --local-install             本地获取安装脚本, 使用当前目录"
    echo -e "  -p, --proxy <addr>              使用代理下载, e.g., -p http://127.0.0.1:2333"
    echo -e "  -v, --core-version <ver>        自定义 $is_core_name 版本, e.g., -v v1.8.13"
    echo -e "  -h, --help                      显示此帮助界面\n"

    exit 0
}

# install dependent pkg
install_pkg() {
    cmd_not_found=
    for i in $*; do
        [[ ! $(type -P $i) ]] && cmd_not_found="$cmd_not_found,$i"
    done
    if [[ $cmd_not_found ]]; then
        pkg=$(echo $cmd_not_found | sed 's/,/ /g')
        msg warn "安装依赖包 >${pkg}"
        if [[ $cmd =~ apk ]]; then
            apk update &>/dev/null
            apk add $pkg &>/dev/null
        else
            $cmd install -y $pkg &>/dev/null
            if [[ $? != 0 ]]; then
                [[ $cmd =~ yum ]] && yum install epel-release -y &>/dev/null
                if [[ $cmd =~ zypper ]]; then
                    $cmd --non-interactive refresh &>/dev/null
                else
                    $cmd update -y &>/dev/null
                fi
                $cmd install -y $pkg &>/dev/null
            fi
        fi
        [[ $? == 0 ]] && >$is_pkg_ok
    else
        >$is_pkg_ok
    fi
}

# download file
download() {
    case $1 in
    core)
        [[ ! $is_core_ver ]] && is_core_ver=$(_wget -qO- "https://api.github.com/repos/${is_core_repo}/releases/latest?v=$RANDOM" | grep tag_name | grep -E -o 'v([0-9.]+)')
        [[ $is_core_ver ]] && link="https://github.com/${is_core_repo}/releases/download/${is_core_ver}/${is_core}-${is_core_ver:1}-linux-${is_arch}.tar.gz"
        name=$is_core_name
        tmpfile=$tmpcore
        is_ok=$is_core_ok
        ;;
    sh)
        link=https://github.com/${is_sh_repo}/releases/latest/download/code.tar.gz
        name="$is_core_name 脚本"
        tmpfile=$tmpsh
        is_ok=$is_sh_ok
        ;;
    jq)
        link=https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-$is_arch
        name="jq"
        tmpfile=$tmpjq
        is_ok=$is_jq_ok
        ;;
    esac

    [[ $link ]] && {
        msg warn "下载 ${name} > ${link}"
        if _wget -t 3 -q -c $link -O $tmpfile; then
            mv -f $tmpfile $is_ok
        fi
    }
}

# get server ip
get_ip() {
    export "$(_wget -4 -qO- https://one.one.one.one/cdn-cgi/trace | grep ip=)" &>/dev/null
    [[ -z $ip ]] && export "$(_wget -6 -qO- https://one.one.one.one/cdn-cgi/trace | grep ip=)" &>/dev/null
}

# check background tasks status
check_status() {
    # dependent pkg install fail
    [[ ! -f $is_pkg_ok ]] && {
        msg err "安装依赖包失败"
        if [[ $cmd =~ apk ]]; then
            msg err "请尝试手动安装依赖包: apk update; apk add $is_pkg"
        else
            msg err "请尝试手动安装依赖包: $cmd update -y; $cmd install -y $is_pkg"
        fi
        is_fail=1
    }

    # download file status
    if [[ $is_wget ]]; then
        [[ ! -f $is_core_ok ]] && {
            msg err "下载 ${is_core_name} 失败"
            is_fail=1
        }
        [[ ! -f $is_sh_ok ]] && {
            msg err "下载 ${is_core_name} 脚本失败"
            is_fail=1
        }
        [[ ! -f $is_jq_ok ]] && {
            msg err "下载 jq 失败"
            is_fail=1
        }
    else
        [[ ! $is_fail ]] && {
            is_wget=1
            [[ ! $is_core_file ]] && download core &
            [[ ! $local_install ]] && download sh &
            [[ $jq_not_found ]] && download jq &
            get_ip
            wait
            check_status
        }
    fi

    # found fail status, remove tmp dir and exit.
    [[ $is_fail ]] && {
        exit_and_del_tmpdir
    }
}

# parameters check
pass_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
        -f | --core-file)
            [[ -z $2 ]] && {
                err "($1) 缺少必需参数, 正确使用示例: [$1 /root/$is_core-linux-amd64.tar.gz]"
            } || [[ ! -f $2 ]] && {
                err "($2) 不是一个常规的文件."
            }
            is_core_file=$2
            shift 2
            ;;
        -l | --local-install)
            [[ ! -f ${PWD}/src/core.sh || ! -f ${PWD}/$is_core.sh ]] && {
                err "当前目录 (${PWD}) 非完整的脚本目录."
            }
            local_install=1
            shift 1
            ;;
        -p | --proxy)
            [[ -z $2 ]] && {
                err "($1) 缺少必需参数, 正确使用示例: [$1 http://127.0.0.1:2333 or -p socks5://127.0.0.1:2333]"
            }
            proxy=$2
            shift 2
            ;;
        -v | --core-version)
            [[ -z $2 ]] && {
                err "($1) 缺少必需参数, 正确使用示例: [$1 v1.8.13]"
            }
            is_core_ver=v${2//v/}
            shift 2
            ;;
        -h | --help)
            show_help
            ;;
        *)
            echo -e "\n${is_err} ($@) 为未知参数...\n"
            show_help
            ;;
        esac
    done
    [[ $is_core_ver && $is_core_file ]] && {
        err "无法同时自定义 ${is_core_name} 版本和 ${is_core_name} 文件."
    }
}

# exit and remove tmpdir
exit_and_del_tmpdir() {
    rm -rf $tmpdir
    [[ ! $1 ]] && {
        msg err "哦豁.."
        msg err "安装过程出现错误..."
        echo -e "反馈问题) https://github.com/${is_sh_repo}/issues"
        echo
        exit 1
    }
    exit
}

# create all commonly supported protocol configs for relay compatibility testing
create_all_protocol_configs() {
    msg ok "批量生成所有协议节点..."
    export ALL_NODES_SERVER_IP="$ip"
    export ALL_NODES_CONF_DIR="$is_conf_dir"
    export ALL_NODES_CORE_DIR="$is_core_dir"
    export ALL_NODES_BIN="$is_core_bin"
    export ALL_NODES_BASE_CONFIG="$is_config_json"

    python3 <<'PY'
import base64
import json
import os
import secrets
import subprocess
import time
from pathlib import Path

server = os.environ.get('ALL_NODES_SERVER_IP') or '127.0.0.1'
conf_dir = Path(os.environ['ALL_NODES_CONF_DIR'])
core_dir = Path(os.environ['ALL_NODES_CORE_DIR'])
core_bin = os.environ['ALL_NODES_BIN']
base_config = os.environ['ALL_NODES_BASE_CONFIG']

conf_dir.mkdir(parents=True, exist_ok=True)
backup_dir = conf_dir / ('all-protocol-backup-' + time.strftime('%Y%m%d-%H%M%S'))
old_files = list(conf_dir.glob('ALL-*.json'))
if old_files:
    backup_dir.mkdir(parents=True, exist_ok=True)
    for item in old_files:
        item.rename(backup_dir / item.name)

uuid = '905eae0e-d5c6-433e-8043-eb35d3ca0dc3'
password = 'uz6BMZ2sw7pJ9Nm04T'
socks_user = 'relaytest'
tls_host = 'www.microsoft.com'
reality_sni = 'www.paypal.com'
reality_private_key = '6IDG_qJieyc56Oqi4CN7KqKf-mbguthGY1As-jIi-EU'
reality_public_key = 'QSzS5cXCdec5tmZ0qZBjY3HC8Dir_f3n6e3_emMtkQw'
tls_key = core_dir / 'bin' / 'tls.key'
tls_cer = core_dir / 'bin' / 'tls.cer'

if not tls_key.exists() or not tls_cer.exists():
    tls_key.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([
        'openssl', 'req', '-x509', '-newkey', 'rsa:2048',
        '-keyout', str(tls_key), '-out', str(tls_cer),
        '-days', '3650', '-nodes', '-subj', f'/CN={tls_host}'
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def b64(data: str) -> str:
    return base64.b64encode(data.encode()).decode().rstrip('=')

def b64json(data: dict) -> str:
    return base64.b64encode(json.dumps(data, separators=(',', ':')).encode()).decode()

def tls(alpn=None):
    data = {'enabled': True, 'key_path': str(tls_key), 'certificate_path': str(tls_cer)}
    if alpn:
        data['alpn'] = alpn
    return data

def ws(path):
    return {'type': 'ws', 'path': path, 'headers': {'host': tls_host}, 'early_data_header_name': 'Sec-WebSocket-Protocol'}

def h2(path):
    return {'type': 'http', 'path': path, 'headers': {'host': tls_host}}

def httpupgrade(path):
    return {'type': 'httpupgrade', 'path': path, 'headers': {'host': tls_host}}

nodes = []

def write_node(name, protocol, port, url, inbound):
    inbound.setdefault('tag', name)
    inbound.setdefault('listen', '::')
    inbound.setdefault('listen_port', port)
    path = conf_dir / f'ALL-{name}.json'
    path.write_text(json.dumps({'inbounds': [inbound], 'outbounds': [{'type': 'direct'}]}, indent=2), encoding='utf-8')
    nodes.append({'name': name, 'protocol': protocol, 'port': port, 'url': url})

def vmess_url(name, port, net, extra=None):
    data = {'v': 2, 'ps': f'ALL-{name}', 'add': server, 'port': str(port), 'id': uuid, 'aid': '0', 'net': net, 'type': 'none'}
    if extra:
        data.update(extra)
    return 'vmess://' + b64json(data)

# 233boy protocol_list compatible nodes.
write_node('tuic', 'TUIC', 24001, f'tuic://{uuid}:{password}@{server}:24001?alpn=h3&insecure=1&allowInsecure=1&congestion_control=bbr#ALL-tuic', {'type': 'tuic', 'users': [{'uuid': uuid, 'password': password}], 'congestion_control': 'bbr', 'tls': tls(['h3'])})
write_node('trojan', 'Trojan', 24002, f'trojan://{password}@{server}:24002?type=tcp&security=tls&insecure=1&allowInsecure=1#ALL-trojan', {'type': 'trojan', 'users': [{'password': password}], 'tls': tls()})
write_node('hysteria2', 'Hysteria2', 24003, f'hysteria2://{password}@{server}:24003?alpn=h3&insecure=1&allowInsecure=1#ALL-hysteria2', {'type': 'hysteria2', 'users': [{'password': password}], 'tls': tls(['h3'])})

write_node('vmess-ws', 'VMess-WS', 24004, vmess_url('vmess-ws', 24004, 'ws', {'host': '', 'path': '/vmessws', 'tls': ''}), {'type': 'vmess', 'users': [{'uuid': uuid}], 'transport': {'type': 'ws', 'path': '/vmessws', 'early_data_header_name': 'Sec-WebSocket-Protocol'}})
write_node('vmess-tcp', 'VMess-TCP', 24005, vmess_url('vmess-tcp', 24005, 'tcp'), {'type': 'vmess', 'users': [{'uuid': uuid}]})
write_node('vmess-http', 'VMess-HTTP', 24006, vmess_url('vmess-http', 24006, 'tcp', {'type': 'http'}), {'type': 'vmess', 'users': [{'uuid': uuid}], 'transport': {'type': 'http'}})
write_node('vmess-quic', 'VMess-QUIC', 24007, vmess_url('vmess-quic', 24007, 'quic', {'tls': 'tls', 'alpn': 'h3', 'allowInsecure': True}), {'type': 'vmess', 'users': [{'uuid': uuid}], 'tls': tls(['h3']), 'transport': {'type': 'quic'}})

write_node('shadowsocks', 'Shadowsocks', 24008, f'ss://{b64("aes-128-gcm:" + password)}@{server}:24008#ALL-shadowsocks', {'type': 'shadowsocks', 'method': 'aes-128-gcm', 'password': password})

write_node('vmess-h2-tls', 'VMess-H2-TLS', 24009, vmess_url('vmess-h2-tls', 24009, 'h2', {'host': tls_host, 'path': '/vmessh2', 'tls': 'tls', 'sni': tls_host, 'allowInsecure': True}), {'type': 'vmess', 'users': [{'uuid': uuid}], 'tls': tls(), 'transport': h2('/vmessh2')})
write_node('vmess-ws-tls', 'VMess-WS-TLS', 24010, vmess_url('vmess-ws-tls', 24010, 'ws', {'host': tls_host, 'path': '/vmesswstls', 'tls': 'tls', 'sni': tls_host, 'allowInsecure': True}), {'type': 'vmess', 'users': [{'uuid': uuid}], 'tls': tls(), 'transport': ws('/vmesswstls')})
write_node('vless-h2-tls', 'VLESS-H2-TLS', 24011, f'vless://{uuid}@{server}:24011?encryption=none&security=tls&type=h2&host={tls_host}&path=/vlessh2&sni={tls_host}&allowInsecure=1&fp=chrome#ALL-vless-h2-tls', {'type': 'vless', 'users': [{'uuid': uuid}], 'tls': tls(), 'transport': h2('/vlessh2')})
write_node('vless-ws-tls', 'VLESS-WS-TLS', 24012, f'vless://{uuid}@{server}:24012?encryption=none&security=tls&type=ws&host={tls_host}&path=/vlesswstls&sni={tls_host}&allowInsecure=1&fp=chrome#ALL-vless-ws-tls', {'type': 'vless', 'users': [{'uuid': uuid}], 'tls': tls(), 'transport': ws('/vlesswstls')})
write_node('trojan-h2-tls', 'Trojan-H2-TLS', 24013, f'trojan://{password}@{server}:24013?security=tls&type=h2&host={tls_host}&path=/trojanh2&sni={tls_host}&allowInsecure=1#ALL-trojan-h2-tls', {'type': 'trojan', 'users': [{'password': password}], 'tls': tls(), 'transport': h2('/trojanh2')})
write_node('trojan-ws-tls', 'Trojan-WS-TLS', 24014, f'trojan://{password}@{server}:24014?security=tls&type=ws&host={tls_host}&path=/trojanwstls&sni={tls_host}&allowInsecure=1#ALL-trojan-ws-tls', {'type': 'trojan', 'users': [{'password': password}], 'tls': tls(), 'transport': ws('/trojanwstls')})
write_node('vmess-httpupgrade-tls', 'VMess-HTTPUpgrade-TLS', 24015, vmess_url('vmess-httpupgrade-tls', 24015, 'httpupgrade', {'host': tls_host, 'path': '/vmesshu', 'tls': 'tls', 'sni': tls_host, 'allowInsecure': True}), {'type': 'vmess', 'users': [{'uuid': uuid}], 'tls': tls(), 'transport': httpupgrade('/vmesshu')})
write_node('vless-httpupgrade-tls', 'VLESS-HTTPUpgrade-TLS', 24016, f'vless://{uuid}@{server}:24016?encryption=none&security=tls&type=httpupgrade&host={tls_host}&path=/vlesshu&sni={tls_host}&allowInsecure=1&fp=chrome#ALL-vless-httpupgrade-tls', {'type': 'vless', 'users': [{'uuid': uuid}], 'tls': tls(), 'transport': httpupgrade('/vlesshu')})
write_node('trojan-httpupgrade-tls', 'Trojan-HTTPUpgrade-TLS', 24017, f'trojan://{password}@{server}:24017?security=tls&type=httpupgrade&host={tls_host}&path=/trojanhu&sni={tls_host}&allowInsecure=1#ALL-trojan-httpupgrade-tls', {'type': 'trojan', 'users': [{'password': password}], 'tls': tls(), 'transport': httpupgrade('/trojanhu')})

write_node('vless-reality', 'VLESS-REALITY', 24018, f'vless://{uuid}@{server}:24018?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp&sni={reality_sni}&pbk={reality_public_key}&fp=chrome#ALL-vless-reality', {'type': 'vless', 'users': [{'uuid': uuid, 'flow': 'xtls-rprx-vision'}], 'tls': {'enabled': True, 'server_name': reality_sni, 'reality': {'enabled': True, 'handshake': {'server': reality_sni, 'server_port': 443}, 'private_key': reality_private_key, 'short_id': ['']}}})
write_node('vless-http2-reality', 'VLESS-HTTP2-REALITY', 24019, f'vless://{uuid}@{server}:24019?encryption=none&security=reality&type=h2&sni={reality_sni}&pbk={reality_public_key}&fp=chrome#ALL-vless-http2-reality', {'type': 'vless', 'users': [{'uuid': uuid}], 'tls': {'enabled': True, 'server_name': reality_sni, 'reality': {'enabled': True, 'handshake': {'server': reality_sni, 'server_port': 443}, 'private_key': reality_private_key, 'short_id': ['']}}, 'transport': {'type': 'http'}})
write_node('anytls', 'AnyTLS', 24020, f'anytls://{password}@{server}:24020?insecure=1&allowInsecure=1#ALL-anytls', {'type': 'anytls', 'users': [{'password': password}], 'tls': tls()})
write_node('socks', 'Socks', 24021, f'socks://{b64(socks_user + ":" + password)}@{server}:24021#ALL-socks', {'type': 'socks', 'users': [{'username': socks_user, 'password': password}]})

manifest = Path('/root/sing-box-all-nodes.txt')
manifest.write_text('\n'.join([node['url'] for node in nodes]) + '\n', encoding='utf-8')
Path('/root/sing-box-all-nodes.json').write_text(json.dumps(nodes, indent=2), encoding='utf-8')

check = subprocess.run([core_bin, 'check', '-c', base_config, '-C', str(conf_dir)], capture_output=True, text=True)
if check.returncode != 0:
    print(check.stdout)
    print(check.stderr)
    raise SystemExit(check.returncode)

print('\n==================== ALL SING-BOX NODES ====================')
for node in nodes:
    print(f"\n[{node['protocol']}] {node['name']} : {node['port']}")
    print(node['url'])
print('\nSaved: /root/sing-box-all-nodes.txt')
print('Saved: /root/sing-box-all-nodes.json')
print('============================================================')
PY
}

# main
main() {

    # check old version
    [[ -f $is_sh_bin && -d $is_core_dir/bin && -d $is_sh_dir && -d $is_conf_dir ]] && {
        err "检测到脚本已安装, 如需重装请使用${green} ${is_core} reinstall ${none}命令."
    }

    # check parameters
    [[ $# -gt 0 ]] && pass_args $@

    # show welcome msg
    clear
    echo
    echo "........... $is_core_name script by $author .........."
    echo

    # start installing...
    msg warn "开始安装..."
    [[ $is_core_ver ]] && msg warn "${is_core_name} 版本: ${yellow}$is_core_ver${none}"
    [[ $proxy ]] && msg warn "使用代理: ${yellow}$proxy${none}"
    # create tmpdir
    mkdir -p $tmpdir
    # if is_core_file, copy file
    [[ $is_core_file ]] && {
        cp -f $is_core_file $is_core_ok
        msg warn "${yellow}${is_core_name} 文件使用 > $is_core_file${none}"
    }
    # local dir install sh script
    [[ $local_install ]] && {
        >$is_sh_ok
        msg warn "${yellow}本地获取安装脚本 > $PWD ${none}"
    }

    if [[ $is_systemd ]]; then
        timedatectl set-ntp true &>/dev/null
        [[ $? != 0 ]] && {
            is_ntp_on=1
        }
    fi

    # install dependent pkg
    if [[ $cmd =~ apk ]]; then
        # Alpine: force install full versions to replace BusyBox applets
        apk update &>/dev/null
        apk add $is_pkg &>/dev/null
        [[ $? == 0 ]] && >$is_pkg_ok
    else
        install_pkg $is_pkg &
    fi

    # jq
    if [[ $(type -P jq) ]]; then
        >$is_jq_ok
    else
        jq_not_found=1
    fi
    # if wget installed. download core, sh, jq, get ip
    [[ $is_wget ]] && {
        [[ ! $is_core_file ]] && download core &
        [[ ! $local_install ]] && download sh &
        [[ $jq_not_found ]] && download jq &
        get_ip
    }

    # waiting for background tasks is done
    wait

    # check background tasks status
    check_status

    # test $is_core_file
    if [[ $is_core_file ]]; then
        mkdir -p $tmpdir/testzip
        tar zxf $is_core_ok --strip-components 1 -C $tmpdir/testzip &>/dev/null
        [[ $? != 0 ]] && {
            msg err "${is_core_name} 文件无法通过测试."
            exit_and_del_tmpdir
        }
        [[ ! -f $tmpdir/testzip/$is_core ]] && {
            msg err "${is_core_name} 文件无法通过测试."
            exit_and_del_tmpdir
        }
    fi

    # get server ip.
    [[ ! $ip ]] && {
        msg err "获取服务器 IP 失败."
        exit_and_del_tmpdir
    }

    # create sh dir...
    mkdir -p $is_sh_dir

    # copy sh file or unzip sh zip file.
    if [[ $local_install ]]; then
        cp -rf $PWD/* $is_sh_dir
    else
        tar zxf $is_sh_ok -C $is_sh_dir
    fi

    # create core bin dir
    mkdir -p $is_core_dir/bin
    # copy core file or unzip core zip file
    if [[ $is_core_file ]]; then
        cp -rf $tmpdir/testzip/* $is_core_dir/bin
    else
        tar zxf $is_core_ok --strip-components 1 -C $is_core_dir/bin
    fi

    # add alias
    echo "alias sb=$is_sh_bin" >>/root/.bashrc
    echo "alias $is_core=$is_sh_bin" >>/root/.bashrc

    # core command
    ln -sf $is_sh_dir/$is_core.sh $is_sh_bin
    ln -sf $is_sh_dir/$is_core.sh ${is_sh_bin/$is_core/sb}

    # jq
    [[ $jq_not_found ]] && mv -f $is_jq_ok /usr/bin/jq

    # chmod
    chmod +x $is_core_bin $is_sh_bin /usr/bin/jq ${is_sh_bin/$is_core/sb}

    # create log dir
    mkdir -p $is_log_dir

    # show a tips msg
    msg ok "生成配置文件..."

    # create service
    load systemd.sh
    is_new_install=1
    install_service $is_core &>/dev/null

    # create condf dir
    mkdir -p $is_conf_dir

    load core.sh
    create_all_protocol_configs
    # wait for background tasks (e.g., OpenRC service start)
    wait
    # remove tmp dir and exit.
    exit_and_del_tmpdir ok
}

# start.
main $@