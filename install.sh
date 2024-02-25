#!/bin/bash


# Check if dialog is installed
if ! command -v dialog &> /dev/null; then
    apk install dialog -y
fi

# Check if whiptail is installed
if ! command -v whiptail &> /dev/null; then
    apk install whiptail -y
fi

# Define partial functions
##############################
## Functions for iptables setup
install_iptables() {
    IP=$(whiptail --inputbox "Enter your main server IP like (1.1.1.1):" 8 60 3>&1 1>&2 2>&3)
    {
        echo "10" "Installing iptables..."
        apk install -y iptables iptables-persistent > /dev/null 2>&1
        echo "30" "Enabling net.ipv4.ip_forward..."
        sysctl net.ipv4.ip_forward=1 > /dev/null 2>&1
        echo "50" "Configuring iptables rules for TCP..."
        iptables -t nat -A POSTROUTING -p tcp --match multiport --dports 80,443 -j MASQUERADE > /dev/null 2>&1
        echo "60" "Configuring iptables rules for TCP DNAT..."
        iptables -t nat -A PREROUTING -p tcp --match multiport --dports 80,443 -j DNAT --to-destination $IP > /dev/null 2>&1
        echo "75" "Configuring iptables rules for UDP..."
        iptables -t nat -A POSTROUTING -p udp -j MASQUERADE > /dev/null 2>&1
        echo "85" "Configuring iptables rules for UDP DNAT..."
        iptables -t nat -A PREROUTING -p udp -j DNAT --to-destination $IP > /dev/null 2>&1
        echo "95" "Creating /etc/iptables/..."
        mkdir -p /etc/iptables/ > /dev/null 2>&1
        iptables-save | tee /etc/iptables/rules.v4 > /dev/null
        echo "100" "Starting iptables service..."
        systemctl start iptables
    } | dialog --title "IPTables Installation" --gauge "Installing IPTables..." 10 100 0
    clear
    whiptail --title "IPTables Installation" --msgbox "IP-Tables Installation completed." 8 60
}

check_port_iptables() {
    ip_ports=$(iptables-save | awk '/-A (PREROUTING|POSTROUTING)/ && /-p tcp -m multiport --dports/ {split($0, parts, "--to-destination "); split(parts[2], dest_port, "[:]"); split(parts[1], src_port, " --dports "); split(src_port[2], port_list, ","); for (i in port_list) { if(dest_port[1] != "") { if (index(port_list[i], " ")) { split(port_list[i], split_port, " "); print dest_port[1], split_port[1] } else print dest_port[1], port_list[i] }}}'
)
    status=$(systemctl is-active iptables)
    service_status="iptables Service Status: $status"
    info="Service Status and Ports in Use:\n$ip_ports\n\n$service_status"
    whiptail --title "iptables Service Status and Ports" --msgbox "$info" 15 70
}

uninstall_iptables() {
    {
        echo "10" "Flushing iptables rules..."
        iptables -F > /dev/null 2>&1
        sleep 1
        echo "20" "Deleting all user-defined chains..."
        iptables -X > /dev/null 2>&1
        sleep 1
        echo "40" "Flushing NAT table..."
        iptables -t nat -F > /dev/null 2>&1
        sleep 1
        echo "50" "Deleting user-defined chains in NAT table..."
        iptables -t nat -X > /dev/null 2>&1
        sleep 1
        echo "70" "Removing /etc/iptables/rules.v4..."
        rm /etc/iptables/rules.v4 > /dev/null 2>&1
        sleep 1
        echo "80" "Stopping iptables service..."
        systemctl stop iptables > /dev/null 2>&1
        sleep 1
        echo "100" "IPTables Uninstallation completed!"
    } | dialog --title "IPTables Uninstallation" --gauge "Uninstalling IPTables..." 10 100 0
    clear
    whiptail --title "IPTables Uninstallation" --msgbox "IPTables Uninstalled." 8 60
}


##########################
## Functions for GOST setup
install_gost() {
    {
    echo "20"
    wget -q https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz
    sleep 1
    echo "40"
    gunzip -q gost-linux-amd64-2.11.5.gz
    sleep 1
    echo "60"
    mv gost-linux-amd64-2.11.5 /usr/local/bin/gost
    sleep 1
    echo "80"
    chmod +x /usr/local/bin/gost
    echo "90"
    wget -q -O /usr/lib/systemd/system/gost.service https://raw.githubusercontent.com/hiddify/hiddify-relay/main/gost.service
    sleep 1
    } | dialog --title "GOST Installation" --gauge "Installing GOST..." 10 60
    
    domain=$(whiptail --inputbox "Enter domain:" 8 60  --title "GOST Installation" 3>&1 1>&2 2>&3)
    port=$(whiptail --inputbox "Enter port number:" 8 60  --title "GOST Installation" 3>&1 1>&2 2>&3)

    sed -i "s|ExecStart=/usr/local/bin/gost -L=tcp://:\$port/\$domain:\$port|ExecStart=/usr/local/bin/gost -L=tcp://:$port/$domain:$port|g" /usr/lib/systemd/system/gost.service > /dev/null 2>&1

    systemctl start gost > /dev/null 2>&1
    systemctl enable gost > /dev/null 2>&1
    status=$(systemctl is-active gost)

    if [ "$status" = "active" ]; then
        whiptail --title "GOST Service Status" --msgbox "Gost tunnel is installed and $status." 8 60
    else
        whiptail --title "GOST Installation" --msgbox "GOST service is not active or $status." 8 60
    fi
    clear
}

check_port_gost() {
    gost_ports=$(lsof -i -P -n -sTCP:LISTEN | grep gost | awk '{print $9}')
    status=$(systemctl is-active gost)
    service_status="gost Service Status: $status"
    info="Service Status and Ports in Use:\n\nPorts in use:\n$gost_ports\n\n$service_status"
    whiptail --title "gost Service Status and Ports" --msgbox "$info" 15 70
}

add_port_gost() {

    last_port=$(lsof -i -P -n -sTCP:LISTEN | grep gost | awk '{print $9}' | awk -F ':' '{print $NF}' | sort -n | tail -n 1)

    new_domain=$(whiptail --inputbox "Enter domain:" 8 60  --title "GOST Installation" 3>&1 1>&2 2>&3)
    new_port=$(whiptail --inputbox "Enter port number:" 8 60  --title "GOST Installation" 3>&1 1>&2 2>&3)

    sed -i "/ExecStart/s/$/ -L=tcp:\/\/:$new_port\/$new_domain:$new_port/" /usr/lib/systemd/system/gost.service > /dev/null 2>&1
    systemctl daemon-reload > /dev/null 2>&1
    systemctl restart gost > /dev/null 2>&1
    whiptail --title "GOST configuration" --msgbox "New domain and port added." 8 60
}

uninstall_gost() {
    {
        echo "20" "Stopping GOST service..."
        systemctl stop gost > /dev/null 2>&1
        sleep 1
        echo "40" "Disabling GOST service..."
        systemctl disable gost > /dev/null 2>&1
        sleep 1
        echo "60" "Reloading systemctl daemon..."
        systemctl daemon-reload > /dev/null 2>&1
        sleep 1
        echo "80" "Removing GOST service and binary..."
        rm -f /usr/lib/systemd/system/gost.service /usr/local/bin/gost
        sleep 1
    } | dialog --title "GOST Uninstallation" --gauge "Uninstalling GOST..." 10 60 0
    clear
    whiptail --title "GOST Uninstallation" --msgbox "GOST Service Uninstalled." 8 60
}

##########################
## Functions for Xray setup

install_xray() {
    bash -c "$(curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install 2>&1 | dialog --title "Xray Installation" --progressbox 30 120

    whiptail --title "Xray Installation" --msgbox "Xray installation completed!" 8 60
    clear
    address=$(whiptail --inputbox "Enter the address:" 8 60 --title "Address Input" 3>&1 1>&2 2>&3)
    port=$(whiptail --inputbox "Enter the port:" 8 60 --title "Port Input" 3>&1 1>&2 2>&3)

    inbound_config=$(cat <<EOF
{
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 62789,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      },
      "tag": "api"
    },
    {
      "listen": null,
      "port": $port,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "$address",
        "followRedirect": false,
        "network": "tcp,udp",
        "port": $port
      },
      "tag": "inbound-1"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ]
}
EOF
)

    echo "$inbound_config" > /usr/local/etc/xray/config.json

    systemctl restart xray
    status=$(systemctl is-active xray)

    if [ "$status" = "active" ]; then
        whiptail --title "Install Xray" --msgbox "Xray installed successfully!" 8 60
    else
        whiptail --title "Install Xray" --msgbox "Xray service is not active or failed." 8 60
    fi

}

check_service_xray() {
    xray_ports=$(lsof -i -P -n -sTCP:LISTEN | grep xray | awk '{print $9}')

    status=$(systemctl is-active xray)
    service_status="Xray Service Status: $status"

    info="Service Status and Ports in Use:\n\nPorts in use:\n$xray_ports\n\n$service_status"

    whiptail --title "Xray Service Status and Ports" --msgbox "$info" 15 70

}

add_another_inbound() {

    addressnew=$(whiptail --inputbox "Enter the new address:" 8 60 --title "Address Input" 3>&1 1>&2 2>&3)
    portnew=$(whiptail --inputbox "Enter the new port:" 8 60 --title "Port Input" 3>&1 1>&2 2>&3)

    position=$(grep -n -m 1 '"tag": "inbound-1"' /usr/local/etc/xray/config.json | cut -d ':' -f1)

    if [ -n "$position" ]; then
        position=$((position + 1))
        sed -i "${position}i \ \ \ \ },\n \ \ \ {\n \ \ \ \ \ \"listen\": null,\n \ \ \ \ \ \"port\": $portnew,\n \ \ \ \ \ \"protocol\": \"dokodemo-door\",\n \ \ \ \ \ \"settings\": {\n \ \ \ \ \ \ \ \"address\": \"$addressnew\",\n \ \ \ \ \ \ \ \"followRedirect\": false,\n \ \ \ \ \ \ \ \"network\": \"tcp,udp\",\n \ \ \ \ \ \ \ \"port\": $portnew\n \ \ \ \ \ },\n \ \ \ \ \ \"tag\": \"inbound-$portnew\"" /usr/local/etc/xray/config.json
        whiptail --title "Install Xray" --msgbox "Additional inbound added." 8 60
        systemctl restart xray
    else
        whiptail --title "Install Xray" --msgbox "Error: Could not find the position to add inbound configuration." 8 60
    fi
}
uninstall_xray() {
    (
    echo "10" "Removing Xray configuration..."
    rm /usr/local/etc/xray/config.json > /dev/null 2>&1
    sleep 1
    echo "30" "Stopping and disabling Xray service..."
    systemctl stop xray && systemctl disable xray > /dev/null 2>&1
    sleep 1
    echo "70" "Uninstalling Xray..."
    bash -c "$(curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove > /dev/null 2>&1
    sleep 1
    echo "100" "Xray Uninstallation completed!"
    sleep 1
    ) | dialog --title "Xray Uninstallation" --gauge "Xray Uninstallation in progress..." 10 100 0
    whiptail --title "Xray Uninstallation" --msgbox "Xray Uninstallation completed!" 8 60
    clear
}

##############################
## Functions for HA-Proxy setup
install_haproxy() {
    {
        echo "10" "Install HAProxy"
        apk install haproxy -y > /dev/null 2>&1
        sleep 1
        echo "30" "Downloading haproxy.cfg..."
        wget -q -O /tmp/haproxy.cfg "https://raw.githubusercontent.com/hiddify/hiddify-relay/main/haproxy.cfg" > /dev/null 2>&1
        sleep 1
        echo "50" "Removing existing haproxy.cfg..."
        rm /etc/haproxy/haproxy.cfg > /dev/null 2>&1
        sleep 1
        echo "70" "Moving new haproxy.cfg to /etc/haproxy..."
        mv /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg
        sleep 1
    } | dialog --title "HAProxy Installation" --gauge "Installing HAProxy..." 10 60 0

    whiptail --title "HAProxy Installation" --msgbox "HAProxy installation completed." 8 60

    target_iport=$(whiptail --inputbox "Enter Relay-Server Free Port:" 8 60 --title "HAProxy Installation" 3>&1 1>&2 2>&3)
    target_ip=$(whiptail --inputbox "Enter Main-Server IP:" 8 60 --title "HAProxy Installation" 3>&1 1>&2 2>&3)
    target_port=$(whiptail --inputbox "Enter Main-Server Port:" 8 60 --title "HAProxy Installation" 3>&1 1>&2 2>&3)

    sed -i "s/\$iport/$target_iport/g; s/\$IP/$target_ip/g; s/\$port/$target_port/g" /etc/haproxy/haproxy.cfg > /dev/null 2>&1

    systemctl restart haproxy > /dev/null 2>&1

    status=$(systemctl is-active haproxy)
    if [ "$status" = "active" ]; then
        whiptail --title "HAProxy Installation" --msgbox "HA-Proxy tunnel is installed and $status." 8 60
    else
        whiptail --title "HAProxy Installation" --msgbox "HA-Proxy service is not active or $status." 8 60
    fi
}

check_haproxy() {
    haproxy_ports=$(lsof -i -P -n -sTCP:LISTEN | grep haproxy | awk '{print $9}')
    status=$(systemctl is-active haproxy)
    service_status="haproxy Service Status: $status"
    info="Service Status and Ports in Use:\n\nPorts in use:\n$haproxy_ports\n\n$service_status"
    whiptail --title "haproxy Service Status and Ports" --msgbox "$info" 15 70
}

uninstall_haproxy() {
    {
        echo "20" "Stopping HAProxy service..."
        systemctl stop haproxy > /dev/null 2>&1
        sleep 1
        echo "40" "Disabling HAProxy service..."
        systemctl disable haproxy > /dev/null 2>&1
        sleep 1
        echo "60" "Removing HAProxy..."
        apk remove --purge haproxy -y > /dev/null 2>&1
        sleep 1
    } | dialog --title "HAProxy Uninstallation" --gauge "Uninstalling HAProxy..." 10 60 0

    whiptail --title "HAProxy Uninstallation" --msgbox "HA-Proxy Uninstalled." 8 60
    clear
}


####################################################
## Function to install Socat and setup tunnel service
install_socat() {
    {
    echo "40" "Install Socat"
    apk install socat -y > /dev/null 2>&1
    sleep 1
    echo "80" "Downloading Socat.service..."
    wget -O /etc/systemd/system/socat.service "https://raw.githubusercontent.com/hiddify/hiddify-relay/main/socat-tunnel.service" > /dev/null 2>&1
    sleep 1
    } | dialog --title "Socat Installation" --gauge "Installing Socat..." 10 60 0

    whiptail --title "Socat Installation" --msgbox "Socat installation completed." 8 60
    clear
    ip=$(whiptail --inputbox "Enter Main-Server IP:" 8 60 --title "Enter IP" 3>&1 1>&2 2>&3)
    port=$(whiptail --inputbox "Enter Main-Server Port:" 8 60 --title "Enter Port" 3>&1 1>&2 2>&3)

    sed -i "s/\$ip/$ip/g" /etc/systemd/system/socat.service > /dev/null 2>&1
    sed -i "s/\$port/$port/g" /etc/systemd/system/socat.service > /dev/null 2>&1

    systemctl daemon-reload > /dev/null 2>&1
    systemctl enable socat > /dev/null 2>&1
    systemctl start socat > /dev/null 2>&1

    status=$(systemctl is-active socat)
    if [ "$status" = "active" ]; then
        whiptail --title "Socat Installation" --msgbox "Socat tunnel is installed and $status." 8 60
    else
        whiptail --title "Socat Installation" --msgbox "Socat service is not active or $status." 8 60
    fi
}

check_socat_port() {
    socat_ports=$(lsof -i -P -n -sTCP:LISTEN | grep socat | awk '{print $9}')
    status=$(systemctl is-active socat)
    service_status="socat Service Status: $status"
    info="Service Status and Ports in Use:\n\nPorts in use:\n$socat_ports\n\n$service_status"
    whiptail --title "Socat Service Status and Ports" --msgbox "$info" 15 70
    clear
}

uninstall_socat() {
    (
        systemctl stop socat > /dev/null 2>&1 && echo "25" && sleep 1 &&
        systemctl disable socat > /dev/null 2>&1 && echo "50" && sleep 1 &&
        rm /etc/systemd/system/socat.service && echo "75" && sleep 1 && > /dev/null 2>&1
        apk remove socat -y > /dev/null 2>&1 && echo "Socat tunnel Uninstalled."
    ) | dialog --title "Socat Uninstallation" --gauge "Uninstalling Socat..." 10 60
    whiptail --title "Socat Uninstallation" --msgbox "Socat tunnel Uninstalled." 8 60
    clear
}

#########################################################
## Function to install wstunnel and setup wstunnel service
install_wstunnel() {
    {
    echo "20"
    wget "https://github.com/erebe/wstunnel/releases/download/v5.0/wstunnel-linux-x64" > /dev/null 2>&1
    sleep 1
    echo "40"
    chmod +x wstunnel-linux-x64 > /dev/null 2>&1
    sleep 1
    echo "60"
    mv wstunnel-linux-x64 /bin/wstunnel > /dev/null 2>&1
    sleep 1
    echo "80"
    rm /etc/systemd/system/wstunnel.service > /dev/null 2>&1
    sleep 1
    echo "90"
    wget -O /etc/systemd/system/wstunnel.service https://raw.githubusercontent.com/Hiddify-Return/hiddify-relay/main/wstunnels.service > /dev/null 2>&1
    sleep 1
    } | dialog --title "Wstunnel Installation" --gauge "Installing Wstunnel..." 10 60
    whiptail --title "wstunnel Installation" --msgbox "wstunnel installation completed." 8 60
    clear
    mport=$(whiptail --inputbox "Enter the port use for traffic(like 443 or any port):" 8 60 --title "Enter IP" 3>&1 1>&2 2>&3)
    domain=$(whiptail --inputbox "Enter the Main-Server domain:" 8 60 --title "Enter domain" 3>&1 1>&2 2>&3)
    port=$(whiptail --inputbox "Enter the port used for wstunnel:" 8 60 --title "Enter wstunnel port" 3>&1 1>&2 2>&3)

    sed -i "s/\$mport/$mport/g; s/\$domain/$domain/g; s/\$port/$port/g" /etc/systemd/system/wstunnel.service > /dev/null 2>&1

    systemctl daemon-reload > /dev/null 2>&1
    systemctl enable wstunnel.service > /dev/null 2>&1
    systemctl start wstunnel.service > /dev/null 2>&1
    clear
    whiptail --title "wstunnel Installation" --msgbox "Now make ssh to main server for setup wstunnel." 8 60

    main_server_ip=$(whiptail --inputbox "Enter the IP of the main server:" 8 60 --title "Enter the main server IP" 3>&1 1>&2 2>&3)
    ssh_user=$(whiptail --inputbox "Enter the user of the main server:" 8 60 --title "Enter the user" 3>&1 1>&2 2>&3)
    main_server_port=$(whiptail --inputbox "Enter the SSH port of the main server (press Enter for default 22): " 8 60 --title "Enter the SSH port" 3>&1 1>&2 2>&3)
    main_server_port=${main_server_port:-22}

    port=$(whiptail --inputbox "Enter the port used for wstunnel:" 8 60 --title "Enter wstunnel port" 3>&1 1>&2 2>&3)

    wget -O wstunnelm.service https://raw.githubusercontent.com/Hiddify-Return/hiddify-relay/main/wstunnelm.service > /dev/null 2>&1
    sed -i "s/\$port/$port/g" wstunnelm.service
    clear
    scp -P $main_server_port wstunnelm.service $ssh_user@$main_server_ip:/tmp/wstunnelm.service
    clear
    whiptail --title "wstunnel Installation" --msgbox "The service file sent to main server." 8 60
    whiptail --title "wstunnel Installation" --msgbox "once again type main server Password:" 8 60
    ssh -p $main_server_port $ssh_user@$main_server_ip << 'ENDSSH'
    mv /tmp/wstunnelm.service /etc/systemd/system/wstunnel.service
    wget "https://github.com/erebe/wstunnel/releases/download/v5.0/wstunnel-linux-x64"
    chmod +x wstunnel-linux-x64
    mv wstunnel-linux-x64 /bin/wstunnel
    systemctl daemon-reload
    systemctl enable wstunnel.service
    systemctl start wstunnel.service
ENDSSH

    clear
    status=$(systemctl is-active wstunnel.service)
    if [ "$status" = "active" ]; then
        whiptail --title "Wstunnel Installation" --msgbox "Wstunnel tunnel is installed and $status." 8 60
    else
        whiptail --title "Wstunnel Installation" --msgbox "Wstunnel service is not active or $status." 8 60
    fi
}

check_wstunnel_port() {
    wstunnel_ports=$(lsof -i -P -n -sTCP:LISTEN | grep wstunnel | awk '{print $9}')
    status=$(systemctl is-active wstunnel)
    service_status="wstunnel Service Status: $status"
    info="Service Status and Ports in Use:\n\nPorts in use:\n$wstunnel_ports\n\n$service_status"
    whiptail --title "wstunnel Service Status and Ports" --msgbox "$info" 15 70
}

uninstall_wstunnel() {
    (
    echo "10" "Stopping wstunnel service..."
    systemctl stop wstunnel.service > /dev/null 2>&1
    sleep 1
    echo "30" "Disabling wstunnel service..."
    systemctl disable wstunnel.service > /dev/null 2>&1
    sleep 1
    echo "70" "Uninstalling wstunnel..."
    rm -f /etc/systemd/system/wstunnel.service /bin/wstunnel
    sleep 1
    echo "100" "wstunnel Uninstallation completed!"
    sleep 1
    ) | dialog --title "wstunnel Uninstallation" --gauge "wstunnel Uninstallation in progress..." 10 100 0
    whiptail --title "wstunnel Uninstallation" --msgbox "wstunnel Uninstallation completed!" 8 60
    clear
    whiptail --title "wstunnel Uninstallation" --msgbox "Use ssh to uninstall Wstunnel form main server" 8 60

    main_server_ip=$(whiptail --inputbox "Enter the IP of the main server:" 8 60 --title "Enter the main server IP" 3>&1 1>&2 2>&3)
    ssh_user=$(whiptail --inputbox "Enter the user of the main server:" 8 60 --title "Enter the user" 3>&1 1>&2 2>&3)
    main_server_port=$(whiptail --inputbox "Enter the SSH port of the main server (press Enter for default 22): " 8 60 --title "Enter the SSH port" 3>&1 1>&2 2>&3)
    main_server_port=${main_server_port:-22}

    # SSH to the main server and execute commands
    ssh -p $main_server_port $ssh_user@$main_server_ip bash -s << 'ENDSSH'
    systemctl stop wstunnel.service
    systemctl disable wstunnel.service
    rm -f /etc/systemd/system/wstunnel.service /bin/wstunnel
ENDSSH
    clear
    whiptail --title "wstunnel Uninstallation" --msgbox "Wstunnel Service Uninstalled." 8 60
}


function configure_dns() {
    rm /etc/resolv.conf > /dev/null 2>&1

    dns1=$(whiptail --inputbox "Enter DNS Server 1(like 8.8.8.8):" 8 60 3>&1 1>&2 2>&3)
    dns2=$(whiptail --inputbox "Enter DNS Server 2(like 8.8.4.4):" 8 60 3>&1 1>&2 2>&3)

    echo "nameserver $dns1" | tee -a /etc/resolv.conf
    echo "nameserver $dns2" | tee -a /etc/resolv.conf

    whiptail --title "DNS Configuration" --msgbox "DNS Configuration completed." 8 60
    clear
}

function update_server() {
    (
        apk update -y
        echo "100" "Update completed."
    ) | dialog --title "Update Server" --progressbox 30 120

    whiptail --title "Update Server" --msgbox "Server Update completed." 8 60
    clear
}

function ping_websites() {
    websites=("github.com" "google.com" "www.microsoft.com")
    results_file=$(mktemp)

    for website in "${websites[@]}"; do
        gauge_title="Pinging $website"
        gauge_percentage=0
        success=false

        (
            for _ in {1..5}; do
                sleep 1  
                ((gauge_percentage += 20))
                echo "$gauge_percentage"
                echo "# $gauge_title"
                echo "Pinging $website..."
                
                if ping -c 1 $website &> /dev/null; then
                    success=true
                fi
            done
            echo "100" 
        ) | dialog --title "Ping $website" --gauge "$gauge_title" 10 80 0

        result=$(ping -c 5 $website | tail -n 2)
        echo -e "\n\nPing results for $website:\n$result" >> "$results_file"
    done

    whiptail --title "Ping Websites" --textbox "$results_file" 30 80
    clear

    rm "$results_file"
}


################################################################
# Define the functions to be executed when an option is selected

# Graphical functionality for IP-Tables menu
iptables_menu() {
    while true; do
        choice=$(whiptail --backtitle "Hiddify Relay Builder" --title "IP-Tables Menu" --menu "Please choose one of the following options:" 20 60 10 \
        "Install" "Install IP-Tables Rules" \
        "Status" "Check Ports In Use" \
        "Uninstall" "Uninstall IP-Tables Rules" \
        "Back" "Back To Main Menu" 3>&1 1>&2 2>&3)

        # Check the return value of the whiptail command
        if [ $? -eq 0 ]; then
            # Check if the user selected a valid option
            case $choice in
                Install)
                    install_iptables
                    ;;
                Status)
                    check_port_iptables
                    ;;
                Uninstall)
                    uninstall_iptables
                    ;;
                Back)
                    menu
                    ;;
                *)
                    whiptail --title "Invalid Option" --msgbox "Please select a valid option." 8 60
                    exit 1
                    ;;
            esac
        else
            exit 1
        fi
    done
}

# Graphical functionality for GOST menu
gost_menu() {
    while true; do
        choice=$(whiptail --backtitle "Hiddify Relay Builder" --title "GOST Menu" --menu "Please choose one of the following options:" 20 60 10 \
        "Install" "Install GOST" \
        "Status" "Check GOST Port And Status" \
        "Add" "Add Another Port And Domain" \
        "Uninstall" "Uninstall GOST" \
        "Back" "Back To Main Menu" 3>&1 1>&2 2>&3)

        # Check the return value of the whiptail command
        if [ $? -eq 0 ]; then
            # Check if the user selected a valid option
            case $choice in
                Install)
                    install_gost
                    ;;
                Status)
                    check_port_gost
                    ;;
                Add)
                    add_port_gost
                    ;;
                Uninstall)
                    uninstall_gost
                    ;;
                Back)
                    menu
                    ;;
                *)
                    whiptail --title "Invalid Option" --msgbox "Please select a valid option." 8 60
                    exit 1
                    ;;
            esac
        else
            exit 1
        fi
    done
}

# Graphical functionality for Dokodemo menu
dokodemo_menu() {
    while true; do
        choice=$(whiptail --backtitle "Hiddify Relay Builder" --title "Dokodemo-Door Menu" --menu "Please choose one of the following options:" 20 60 10 \
        "Install" "Install Xray For Dokodemo-Door And Add Inbound" \
        "Status" "Check Xray Service Status" \
        "Add" "Add Another Inbound" \
        "Uninstall" "Uninstall Xray And Tunnel" \
        "Back" "Back To Main Menu" 3>&1 1>&2 2>&3)

        # Check the return value of the whiptail command
        if [ $? -eq 0 ]; then
            # Check if the user selected a valid option
            case $choice in
                Install)
                    install_xray
                    ;;
                Status)
                    check_service_xray
                    ;;
                Add)
                    add_another_inbound
                    ;;
                Uninstall)
                    uninstall_xray
                    ;;
                Back)
                    menu
                    ;;
                *)
                    whiptail --title "Invalid Option" --msgbox "Please select a valid option." 8 60
                    exit 1
                    ;;
            esac
        else
            exit 1
        fi
    done
}

# Graphical functionality for Socat menu
haproxy_menu() {
    while true; do
        choice=$(whiptail --backtitle "Hiddify Relay Builder" --title "HA-Proxy Menu" --menu "Please choose one of the following options:" 20 60 10 \
        "Install" "Install HA-Proxy" \
        "Status" "Check HA-Proxy Port and Status" \
        "Uninstall" "Uninstall HAProxy" \
        "Back" "Back To Main Menu" 3>&1 1>&2 2>&3)

        # Check the return value of the whiptail command
        if [ $? -eq 0 ]; then
            # Check if the user selected a valid option
            case $choice in
                Install)
                    install_haproxy
                    ;;
                Status)
                    check_haproxy
                    ;;
                Uninstall)
                    uninstall_haproxy
                    ;;
                Back)
                    menu
                    ;;
                *)
                    whiptail --title "Invalid Option" --msgbox "Please select a valid option." 8 60
                    exit 1
                    ;;
            esac
        else
            exit 1
        fi
    done
}

# Graphical functionality for Socat menu
socat_menu() {
    while true; do
        choice=$(whiptail --backtitle "Hiddify Relay Builder" --title "Socat Menu" --menu "Please choose one of the following options:" 20 60 10 \
        "Install" "Install Socat And Setup Tunnel Service" \
        "Status" "Check Socat Port" \
        "Uninstall" "Uninstall Socat And Remove Tunnel Service" \
        "Back" "Back To Main Menu" 3>&1 1>&2 2>&3)

        # Check the return value of the whiptail command
        if [ $? -eq 0 ]; then
            # Check if the user selected a valid option
            case $choice in
                Install)
                    install_socat
                    ;;
                Status)
                    check_socat_port
                    ;;
                Uninstall)
                    uninstall_socat
                    ;;
                Back)
                    menu
                    ;;
                *)
                    whiptail --title "Invalid Option" --msgbox "Please select a valid option." 8 60
                    exit 1
                    ;;
            esac
        else
            exit 1
        fi
    done
}

# Graphical functionality for WSTunnel menu
wstunnel_menu() {
    while true; do
        choice=$(whiptail --backtitle "Hiddify Relay Builder" --title "WS-Tunnel Menu" --menu "Please choose one of the following options:" 20 60 10 \
        "Install" "Install And Configure WS-Tunnel" \
        "Status" "Check WS-Tunnel Service And Port" \
        "Uninstall" "Uninstall WS-Tunnel From Both Servers" \
        "Back" "Back To Main Menu" 3>&1 1>&2 2>&3)

        # Check the return value of the whiptail command
        if [ $? -eq 0 ]; then
            # Check if the user selected a valid option
            case $choice in
                Install)
                    install_wstunnel
                    ;;
                Status)
                    check_wstunnel_port
                    ;;
                Uninstall)
                    uninstall_wstunnel
                    ;;
                Back)
                    menu
                    ;;
                *)
                    whiptail --title "Invalid Option" --msgbox "Please select a valid option." 8 60
                    exit 1
                    ;;
            esac
        else
            exit 1
        fi
    done
}
# Define the submenu for Other Options
function other_options_menu() {
    while true; do
        other_choice=$(whiptail --backtitle "Welcome to Hiddify Relay Builder" --title "Other Options" --menu "Please choose one of the following options:" 20 60 10 \
        "DNS" "Configure DNS" \
        "Update" "Update Server" \
        "Ping" "Ping to check internet connectivity" \
        "Back" "Return to Main Menu" 3>&1 1>&2 2>&3)

        # Check the return value of the whiptail command
        if [ $? -eq 0 ]; then
            # Check if the user selected a valid option
            case $other_choice in
                DNS)
                    configure_dns
                    ;;
                Update)
                    update_server
                    ;;
                Ping)
                    ping_websites
                    ;;
                Back)
                    menu
                    ;;
                *)
                    whiptail --title "Invalid Option" --msgbox "Please select a valid option." 8 60
                    ;;
            esac
        else
            exit 1
        fi
    done
}
#################################
# Define the main graphical menu
function menu() {
    while true; do
        choice=$(whiptail --backtitle "Welcome to Hiddify Relay Builder" --title "Choose Your Tunnel Mode" --menu "Please choose one of the following options:" 20 60 10 \
        "IP-Tables" "Manage IP-Tables Tunnel" \
        "GOST" "Manage GOST Tunnel" \
        "Dokodemo-Door" "Manage Dokodemo-Door Tunnel" \
        "HA-Proxy" "Manage HA-Proxy Tunnel" \
        "Socat" "Manage Socat Tunnel" \
        "WST" "Manage Web Socket Tunnel" \
        "Options" "Additional Configuration Options" \
        "Quit" "Exit From The Script" 3>&1 1>&2 2>&3)

        # Check the return value of the whiptail command
        if [ $? -eq 0 ]; then
            # Check if the user selected a valid option
            case $choice in
                IP-Tables)
                    iptables_menu
                    ;;
                GOST)
                    gost_menu
                    ;;
                Dokodemo-Door)
                    dokodemo_menu
                    ;;
                HA-Proxy)
                    haproxy_menu
                    ;;
                Socat)
                    socat_menu
                    ;;
                WST)
                    wstunnel_menu
                    ;;
                Options)
                    other_options_menu
                    ;;
                Quit)
                    exit 0
                    ;;
                *)
                    whiptail --title "Invalid Option" --msgbox "Please select a valid option." 8 60
                    exit 1
                    ;;
            esac
        else
            exit 1
        fi
    done
}

# Call the menu function
menu
