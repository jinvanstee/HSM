# PKCS11-proxy deployment as a standalone Docker container
In order for your IBM Blockchain Platform nodes to use your IBM Z openCryptoki HSM to manage its private key, you must create a PKCS #11 proxy that allows the blockchain nodes to communicate with the Z-HSM. This README describes how to build the PKCS #11 proxy into a Docker image and then deploy it to a Linux Virtual Machine on s390x. After you complete this process, you will have the values of the HSM proxy endpoint, HSM Label, and HSM PIN that are required by the IBM Blockchain Platform node to use the Z HSM.

Please note that the official supported way of having IBP use the Z HSM is documented [here](https://github.com/IBM-Blockchain/HSM/tree/master/Z-HSM). This repo leverages assets from the aforementioned repo and documents a workaround to integrate with the Z-HSM. This workaround has been verified on Ubuntu 18.04 on Linux on IBM Z. Please also note that this is not a highly available workaround as it only sets up one pkcs11-proxy that is backed by one Z HSM adapter/domain pair.

## Prerequisites
* A Linux system on s390x to host the pkcs11-proxy container.
* The IBM Blockchain Platform nodes have network access to the Linux system on s390x.
* The Linux system must be enabled with the EP11 stack. Please see [here](https://www.ibm.com/support/knowledgecenter/linuxonibm/com.ibm.linux.z.lxce/lxce_building_stack.html) for full instructions on enabling the EP11 stack for your Linux on s390x system.

## Step 1. Configuring openCryptoki for EP11
After you have enabled your s390x Linux system with the EP11 stack, please go through this [documentation](https://www.ibm.com/support/knowledgecenter/linuxonibm/com.ibm.linux.z.lxce/lxce_configuring_ocryptoki_ep11tok.html) to configure openCryptoki for EP11 support. 

I will share in this repo the configuration files that I used for your reference, but it is strongly advised to go through the documentation yourself to understand all the options and settings available to you.

### /etc/opencryptoki/opencryptoki.conf:

Below is my openCryptoki configuration file. I have removed the slots that aren't applicable to my configuration from the default configuration file, and kept the EP11 slot which is slot 4 by default. Please note that you may have a newer version of opencryptoki. Again I would reference the [official documentation](https://www.ibm.com/support/knowledgecenter/linuxonibm/com.ibm.linux.z.lxce/lxce_configuring_ocryptoki_ep11tok.html) for the latest available options.

```
version opencryptoki-3.1

slot 4
{
stdll = libpkcs11_ep11.so
confname = ep11tok.conf
tokname = ep11tok
}
```

### /etc/opencryptoki/ep11tok.conf:

Below is my ep11 token configuration file. This file is referenced by the `/etc/opencryptoki/opencryptoki.conf` file.

```
APQN_WHITELIST
 8 0x15
END
```

The term APQN stands for adjunct processor queue number. It designates the combination of a cryptographic coprocessor (adapter) and a domain, a so-called adapter/domain pair. At least one adapter/domain pair must be specified. For more information on the options available for this configuration file, please see [here](https://www.ibm.com/support/knowledgecenter/linuxonibm/com.ibm.linux.z.lxce/lxce_ep11_conffile.html).

Please make sure that the configuration matches your crypto adapter and domain. You can find out what yours are with the `lszcrypt` command. For example, the `lszcrypt` output that corresponds to the above ep11 token configuration file is:

```
$ lszcrypt
CARD.DOMAIN TYPE  MODE        STATUS  REQUEST_CNT
-------------------------------------------------
08          CEX6P EP11-Coproc online            8
08.0015     CEX6P EP11-Coproc online            8
``` 

###  Start the slot daemon

Use one of the following command to start the slot daemon, which reads out the configuration information and sets up the tokens:

```
$ service pkcsslotd start 
```

or
```
$ systemctl start pkcsslotd.service   /* for Linux distributions providing systemd */
```

You might need to have `sudo` authority to run the above command.

For a permanent solution, specify:
```
$ chkconfig pkcsslotd on
```

### Initialize the EP11 token

Once the openCryptoki configuration file and the configuration files of the EP11 tokens are set up, and the pkcsslotd daemon is started, the EP11 token instances must be initialized. See this [documentation](https://www.ibm.com/support/knowledgecenter/linuxonibm/com.ibm.linux.z.lxce/lxce_initializing_ep11token.html) for step by step instructions on how to do this. 

After this process, you should have the following information to pass into the Docker container:

```
EP11_SLOT_NO=4
EP11_SLOT_TOKEN_LABEL=EP11Tok
EP11_SLOT_SO_PIN=12345678
EP11_SLOT_USER_PIN=84959689
```

You need to change the values to the values you set during your initialization steps.

To verify that the EP11 token has been initialized, run the following command:

```
$ sudo pkcsconf -t
```

Example output:

```
Token #4 Info:
	Label: EP11Tok                        
	Manufacturer: IBM Corp.                       
	Model: IBM EP11Tok     
	Serial Number: 123             
	Flags: 0x44D (RNG|LOGIN_REQUIRED|USER_PIN_INITIALIZED|CLOCK_ON_TOKEN|TOKEN_INITIALIZED)
	Sessions: 0/18446744073709551614
	R/W Sessions: 18446744073709551615/18446744073709551614
	PIN Length: 4-8
	Public Memory: 0xFFFFFFFFFFFFFFFF/0xFFFFFFFFFFFFFFFF
	Private Memory: 0xFFFFFFFFFFFFFFFF/0xFFFFFFFFFFFFFFFF
	Hardware Version: 1.0
	Firmware Version: 1.0
	Time: 15:47:21

```

## Step 2. Build the Docker image

Clone this repo to your Linux on s390x system. Before you can build the Docker image, you need to provide your HSM slot number, HSM slot label, initialization code, and PIN by editing the [`entrypoint.sh`](./docker-image/entrypoint.sh) file. This file is used to initialize the Docker container, by passing the required setup steps to the container.

Replace the following variables in the file with the ones you setup in the previous step:

- **`<EP11_SLOT_TOKEN_LABEL>`**: Specify the token label of the slot to use. **Record this value because it is required when you configure an IBM Blockchain Platform node to use this HSM.**
- **`<EP11_SLOT_SO_PIN>`**: Specify the initialization code of the slot.
- **`<EP11_SLOT_USER_PIN>`**: Specify the HSM PIN for the slot. **Record this value because it is required when you configure an IBM Blockchain Platform node to use this HSM.**

Note if you used a slot number other than the default 4 for your EP11 token, then you need to update the variable **EP11_SLOT_NO** as well.

### `entrypoint.sh` Template
```sh
#!/bin/bash -ux

EXISTED_EP11TOK=$(ls /var/lib/opencryptoki)
if [ -z "$EXISTED_EP11TOK" ]
then
  ## It's empty, then using default token configured
  echo "Copy content for /var/lib/opencryptoki"
  cp -rf /install/opencryptoki/* /var/lib/opencryptoki/
else
  ## using existed configured data
  echo "To use existed configuration!"
fi

EXISTED_CFG=$(ls /etc/opencryptoki)
if [ -z "$EXISTED_CFG" ]
then
  ## It's empty, then using default config
  echo "Copy content for /var/lib/opencryptoki"
  cp -rf /install/config/* /etc/opencryptoki/
else
  ## using existed configured data
  echo "To use existed configuration!"
fi

service pkcsslotd start

SLOT_NO=${EP11_SLOT_NO:-4}
SLOT_TOKEN_LABEL=${EP11_SLOT_TOKEN_LABEL:-"<EP11_SLOT_TOKEN_LABEL>"}
SLOT_SO_PIN=${EP11_SLOT_SO_PIN:-"<EP11_SLOT_SO_PIN>"}
SLOT_USER_PIN=${EP11_SLOT_USER_PIN:-"<EP11_SLOT_USER_PIN>"}

EXISTED_LABEL=$(pkcsconf -t | grep -w ${SLOT_TOKEN_LABEL})
if [ -z "$EXISTED_LABEL" ]
then
  echo "initialized slot: "${SLOT_NO}
  printf "87654321\n${SLOT_TOKEN_LABEL}\n" | pkcsconf -I -c ${SLOT_NO}
  printf "87654321\n${SLOT_SO_PIN}\n${SLOT_SO_PIN}\n" | pkcsconf -P -c ${SLOT_NO}
  printf "${SLOT_SO_PIN}\n${SLOT_USER_PIN}\n${SLOT_USER_PIN}\n" | pkcsconf -u -c ${SLOT_NO}
else
  echo "The slot already initialized!"
fi

pkcs11-daemon /usr/lib/s390x-linux-gnu/pkcs11/PKCS11_API.so
```

## Build Docker image

Run the following command to build the Docker image:

```
docker build -t pkcs11-proxy-opencryptoki:s390x-1.0.0 -f Dockerfile .
```

This command is also provided in the [docker-image-build.sh](./docker-image/docker-image-build.sh) file.

## Step 3. Run pkcs11-proxy Docker container

To deploy the newly built `pkcs11-proxy-opencryptoki` image, edit the shell script provided in [run-docker.sh](./deployment/run-docker.sh) to match your EP11 initialization details (If you didn't do this directly in [entrypoint.sh](./docker-image/entrypoint.sh) back in Step 2, you can choose to pass the variables in this file to your running Docker container instead). Deploy the Docker container with:

`. deployment/run-docker.sh
`

Check the Docker container logs with `docker logs <containder name> | tail -3`. You should see the following to indicate that the pkcs11-proxy is listening for incoming requests.

```
+ pkcs11-daemon /usr/lib/s390x-linux-gnu/pkcs11/PKCS11_API.so
pkcs11-proxy[20]: Listening on: tcp://0.0.0.0:2345
```

The container can be reached at `tcp://<your-Linux-system-ip>:2345` and you will need to supply this information when you are configuring your IBM Blockchain Platform nodes to use the Z HSM via the pkcs11-proxy.

## Step 4. Configure IBM Blockchain Platform to use the pkcs11-proxy

When configuring certificate authorities, peers, or ordering service nodes to use your HSM, you need to supply the following information:

```
HSM proxy endpoint: tcp://<your-Linux-system-ip>:2345
HSM label: <your token label, i.e. EP11Tok>
HSM pin: <your token user pin, i.e. 84959689>
```

Upon a successful IBP node deploy, you should see in the container log of the node messages similar to the following:

```
2020/04/15 23:20:56 [DEBUG] Initializing BCCSP with PKCS11 options &{SecLevel:256 HashFamily:SHA2 Ephemeral:false FileKeystore:0xc0018d87d0 DummyKeystore:<nil> Library:/usr/local/lib/libpkcs11-proxy.so Label:EP11Tok Pin:84959689 SoftVerify:false Immutable:false}
WARNING: IGNORING: C_Initialize called twice for same process
2020/04/15 23:20:56 [DEBUG] Initialize key material
2020/04/15 23:20:56 [DEBUG] Making CA filenames absolute
2020/04/15 23:20:56 [WARNING] &{69 The specified CA certificate file /data/org3ca/tlsca/ca-cert.pem does not exist}
2020/04/15 23:20:56 [DEBUG] Root CA certificate request: {CN:tlsca Names:[{C:US ST:North Carolina L: O:Hyperledger OU:Fabric SerialNumber:}] Hosts:[localhost] KeyRequest:0xc000c1ba80 CA:0xc0011664b0 SerialNumber:}
2020/04/15 23:20:56 [INFO] generating key: &{A:ecdsa S:256}
2020/04/15 23:20:56 [DEBUG] generate key from request: algo=ecdsa, size=256
2020-04-15 23:20:56.299 UTC [bccsp_p11] generateECKey -> INFO 002 Generated new P11 key, SKI fe8af6addca3305735e8fa166cd16cc74fddbd2edb4951eaa602b84c1d579c05
2020/04/15 23:20:56 [INFO] encoded CSR
2020/04/15 23:20:56 [DEBUG] validating configuration
2020/04/15 23:20:56 [DEBUG] validate local profile
2020/04/15 23:20:56 [DEBUG] profile is valid
2020/04/15 23:20:56 [INFO] signed certificate with serial number 441149712754399999144436818013463799483598864801
2020/04/15 23:20:56 [INFO] The CA key and certificate were generated for CA tlsca
2020/04/15 23:20:56 [INFO] The key was stored by BCCSP provider 'PKCS11'
2020/04/15 23:20:56 [INFO] The certificate is at: /data/org3ca/tlsca/ca-cert.pem
```

On the Linux system that is hosting the `pkcs11-proxy-opencryptoki` container you can also check the logs of the proxy container, and you should see messages similar to the following (you'll see different session numbers and client IP and port numbers):

```
pkcs11-proxy[20]: New session 1247940441-1627268567 (client 192.168.22.82, port 5767)

pkcs11-proxy[20]: Session 77 stored in position 0
```

On the same Linux system, you can also run `lszcrypt` to see the request count increase:

```
$ lszcrypt
CARD.DOMAIN TYPE  MODE        STATUS  REQUEST_CNT
-------------------------------------------------
08          CEX6P EP11-Coproc online           20
08.0015     CEX6P EP11-Coproc online           20
```

# The end
