# Full-Mesh VPN Performance Evaluation for a Secure-Edge Cloud Continuum

Cite as: *Kjorveziroski V, Bernad C, Gilly K, Filiposka S. Full-mesh VPN performance evaluation for a secure edge-cloud continuum. Softw: Pract Exper. 2024; 1-22. doi: 10.1002/spe.3329*

# Deploying a Kubernetes Cluster

## Installing K3s

- Deploying a master node using K3s:

```bash
export INSTALL_K3S_VERSION='v1.22.17+k3s1'
export VPN_INTERFACE_IP='100.64.0.1'

curl -sfL https://get.k3s.io | sh -s - server \
--node-taint CriticalAddonsOnly=true:NoExecute \
--tls-san distkube.mrezhi.net \
--tls-san $VPN_INTERFACE_IP \
--disable=traefik \
--flannel-backend=none \
--disable-network-policy \
--disable=servicelb \
--write-kubeconfig-mode 664 \
--cluster-cidr=10.138.0.0/16 \
--advertise-address=$VPN_INTERFACE_IP \
--bind-address=$VPN_INTERFACE_IP \
--node-ip=$VPN_INTERFACE_IP \
--node-external-ip=$VPN_INTERFACE_IP
```

- Deploying a worker node using K3s:
  1. Obtain the registration token from an already deployed master node:

        ```bash
        cat /var/lib/rancher/k3s/server/node-token
        ```

  2. Install the agent, customizing the `K3S_URL` and `--node-ip` arguments:

        ```bash
        export INSTALL_K3S_VERSION=v1.22.17+k3s1
        curl -sfL https://get.k3s.io | K3S_URL=https://100.64.0.4:6443 K3S_TOKEN=example-token sh -s - agent --node-ip=100.64.0.2 \
        --node-external-ip=100.64.0.2
        ```

## Calico Installation

1. Install CRDs:

    ```bash
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/tigera-operator.yaml
    ```

2. Download initial config manifests:

    ```bash
    curl https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/custom-resources.yaml -O
    ```

3. Edit the manifests, altering these settings at a minimum:
    - `encapsulation: VXLAN` - enable VXLAN encapsulation **always**, important for traffic to be able to pass seamlessly across the full-mesh Wireguard topology.
    - `cidr: 10.136.0.0/16`

4. Apply the configuration:

    ```bash
     kubectl create -f custom-resources.yaml --save-config
    ```

5. Since Tailscale, Headscale, and Netbird use an MTU of 1280 by default, the VXLAN interface's MTU needs to be altered to 1230 (more details on [Calico's Docs](https://docs.tigera.io/calico/latest/networking/configuring/mtu)):

    ```bash
    kubectl patch installation.operator.tigera.io default --type merge -p '{"spec":{"calicoNetwork":{"mtu":1230}}}'
    ```

# Benchmarks Description

## Conditions

- MTU is 1230 across all clusters (and not 1450). This is because Tailscale by default uses 1280 MTU.

## Setup

- Increase UDP window sizes on all Kubernetes nodes taking part in the benchmarks (necessary for iperf3 UDP tests):

```bash
sysctl -w net.core.rmem_max=26214400
sysctl -w net.core.wmem_max=26214400
sysctl fs.inotify.max_user_instances=512
```

- Add arbitrary latency or delay to each packet going through an interface using the tc tool:

```bash
tc qdisc add dev enp5s0f0 root netem loss 10%
tc qdisc del dev enp5s0f0 root netem loss 10%

tc qdisc add dev enp5s0f0 root netem delay 50ms
tc qdisc del dev enp5s0f0 root netem delay 50ms
```

- Contact the Kubernetes API server from within a pod (with the necessary ServiceAccount already associated) already running in the cluster:

```bash
curl -k https://kubernetes.default.svc/api/v1/pods --header "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
```

- Contact the Kubernetes API server from a third-party node, not part of the cluster:

```
TOKEN=example-token
KUBE_API_SERVER=127.0.0.1

curl -k -H "Authorization: Bearer $TOKEN" -L https://$KUBE_API_SERVER:6443/api/v1/pods
hey -n 1000 -c 10 -m GET -H "Authorization: Bearer $TOKEN" https://$KUBE_API_SERVER:6443/api/v1/pods
```

## VPN Setup

When testing relaying performance, in case each node is in a separate VLAN, it is best to restrict communication using a network level firewall. Otherwise, when L2 reachability is available, a host level firewall can be used, such as iptables.

### Headscale/Tailscale

To prevent DNS issues, bring up the Tailscale client using `--accept-dns=false`. Otherwise, if there is a wildcard DNS record for the tailnet's name, DNS resolution will not work, since by default `ndots` is set to `5` in Kubernetes clusters.

```bash
HEADSCALE_URL='https://example.com'
tailscale up --login-server $HEADSCALE_URL --accept-dns=false
```

#### DERP Deployment

```bash
DERP_HOSTNAME=derp.example.com
go install tailscale.com/cmd/derper@main
./derper -certmode manual --hostname $DERP_HOSTNAME -certdir /root/derp-certs/
```


#### Force DERP

In case each nodes is in a separate VLAN, it is best to restrict communication using a network level firewall. Otherwise, when L2 reachability is available, a host level firewall can be used, such as iptables:

```bash
iptables -I INPUT -p udp -m udp --dport 41641 -j DROP
```

### Netbird

Must blacklist the Calico interfaces to avoid loops. Netbird, similarly to Tailscale allocates IP address from the CG-NAT range by default.

```bash
NETBIRD_MANAGEMENT='https://netbird.example.com:33073'
SETUP_KEY='secret-setup-key'

netbird up --management-url $NETBIRD_MANAGEMENT --setup-key $SETUP_KEY
```

#### Netbird Relaying

Currently only UDP over TURN is supported. 

There is flapping when using the TURN server, so we had to use a development version of the Netbird client. The changes are as follows:

Editing the systemd unit file in `/etc/systemd/system/netbird` and adding the following environment variable:

```
Environment="NB_ICE_FORCE_RELAY_CONN=true"
```

Compiling from source the following Netbird client version (the patch as of this writing still has not been merged into master) - https://github.com/netbirdio/netbird/pull/904/files. The branch name is `feature/env_settings_in_conn`.

Compilation is done using:

```
git clone https://github.com/netbirdio/netbird
git checkout feature/env_settings_in_conn
cd client
go mod tidy
go build .
```

#### Force Coturn

```bash
sudo iptables -I INPUT -i enp5s0f0 -s 192.168.72.23 -p udp -j DROP
sudo iptables -I INPUT -i enp5s0f0 -s 192.168.72.22 -p udp -j DROP
sudo iptables -I INPUT -i enp5s0f0 -s 192.168.72.21 -p udp -j DROP
```

```bash
sudo iptables -D INPUT -i enp5s0f0 -s 192.168.72.23 -p udp -j DROP
sudo iptables -D INPUT -i enp5s0f0 -s 192.168.72.22 -p udp -j DROP
sudo iptables -D INPUT -i enp5s0f0 -s 192.168.72.21 -p udp -j DROP
```

```bash
sudo iptables -I INPUT -i enp5s0f0 -s 192.168.72.0/24 -p udp -j DROP
sudo iptables -I OUTPUT -o enp5s0f0 -d 192.168.72.0/24 -p udp -j DROP
```

### ZeroTier

Must blacklist the Calico interface to avoid loops. When creating a network, it is possible to specify the network's subnet, it does not have to be in the CG-NAT range, as with Tailscale and Netbird.

#### Using a custom planet instead of a moon

Source: https://byteage.com/157.html
Web Archive Link: https://web.archive.org/web/20230409052328/https://byteage.com/157.html
Google Translate can be used to translate the page.

#### Deploying a TCP proxy

- Source: https://discuss.zerotier.com/t/tcp-fallback-doesnt/11773/2

1. Download, compile, and run https://github.com/zerotier/ZeroTierOne/tree/dev/tcp-proxy
2. Edit the client nodes configuration file located in `/var/lib/zerotier-one/local.conf`:

```json
{
  "settings": {
    "tcpFallbackRelay": "192.168.72.24/443",
    "forceTcpRelay": true
  }
}
```

Note that with this approach the connection to the moons will be relayed through this TCP proxy. You still need to deploy your own moon.

#### Updating MTU

Updating a ZeroTier's network MTU, to match the default of Headscale and Netbird:

```bash
CONTROLLER_HOST='127.0.0.1:9993'
NWID=12345
TOKEN=secret-token

curl -vvv -X POST "http://${CONTROLLER_HOST}/controller/network/${NWID}/" -H "X-ZT1-AUTH: ${TOKEN}"  -d '{"mtu": 1280}'
```

#### Allocating IP space

```bash
CONTROLLER_HOST='127.0.0.1:9993'
NWID=12345
TOKEN=secret-token

curl -X POST "http://${CONTROLLER_HOST}/controller/network/${NWID}/" -H "X-ZT1-AUTH: ${TOKEN}" \
-d '{"ipAssignmentPools": [{"ipRangeStart": "192.168.193.1", "ipRangeEnd": "192.168.193.254"}], "routes": [{"target": "192.168.193.0/24", "via": null}], "v4AssignMode": "zt", "private": true }'
```

## Run Benchmarks

The `scripts` directory contains the necessary scripts for evaluating the TCP and UDP throughput perfromance of the VPN solutions, as well as the Kubernetes API response time.

To start, clone the [InfraBuilder/k8s-bench-suite](https://github.com/InfraBuilder/k8s-bench-suite) repository, copy the `scripts/knb-run.sh` script to its root, alter the configuration variables and execute it.

To evaluate the Kubernetes API response time, create the necessary ServiceAccount and ClusterRoleBinding using the manifests present in the `scripts/rbac` directory. Afterwards, the `benchmark-api.sh` script can be altered and executed.
