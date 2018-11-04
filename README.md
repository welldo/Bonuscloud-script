# Bonuscloud-script

第一步：修改bxc.sh

```

BXC_EMAIL="abc@abc.com"

BXC_BCODE="xxxxxxx"
```
第二步：上传至/etc/storage/bxc

第三步：初始化

```

chmod -R 777 /etc/storage/bxc

/etc/storage/bxc/bxc.sh init

/etc/storage/bxc/bxc.sh start

```
第四步：开机脚本中添加语句

```

/etc/storage/bxc/bxc.sh start

```
