# keepalived+LVS 实现双机热备、负载均衡、失效转移 高性能 高可用 高伸缩性 服务器集群
文章来源:[https://www.cnblogs.com/painsOnline/p/5177464.html](https://www.cnblogs.com/painsOnline/p/5177464.html)

## 第一步：配置各个服务器IP
* /etc/init.d/functions 要给755权限新建lvsrs文件,内容如下:
```
#!/bin/bash
#开启或关闭real server 服务

VIP=192.168.138.200
./etc/rc.d/init.d/functions
case "$1" in
        start)
        echo "Start LVS of Real Server 3"
        /sbin/ifconfig lo:0 $VIP broadcast $VIP netmask 255.255.255.255 up
        echo "1" >/proc/sys/net/ipv4/conf/lo/arp_ignore
        echo "2" >/proc/sys/net/ipv4/conf/lo/arp_announce
        echo "1" >/proc/sys/net/ipv4/conf/all/arp_ignore
        echo "2" >/proc/sys/net/ipv4/conf/all/arp_announce
        ;;
        stop)
        /sbin/ifconfig lo:0 down
        echo "Close LVS Director Server"
        echo "0" >/proc/sys/net/ipv4/conf/lo/arp_ignore
        echo "0" >/proc/sys/net/ipv4/conf/lo/arp_announce
        echo "0" >/proc/sys/net/ipv4/conf/all/arp_ignore
        echo "0" >/proc/sys/net/ipv4/conf/all/arp_announce
        ;;
        *)
        echo "Usage:$0 {start|stop}"
        exit 1
esac
```

* 然后放到 '/etc/init.d/lvsrs' 并赋予权限 755

##第二步：在主、备 director server 上安装 keepalived ipvsadm 等软件
* yum -y install kernel-devel kernel  安装lvs(基本自带有的)
* yum install ipvsadm	安装ipvsadm(查看虚拟网络状况)
* yum -y install keepalived	安装keepalived,构建虚拟ip组并检测各ip的健康状态

## 第三步：配置keepalived(位置在/etc/keepalived/keepalived.conf) 
> master机上的keepalived.conf:
```
#这里是全局定义部分
global_defs {
   notification_email {
    admin@morshoo.com   #设置报警邮件地址 每行一个 可以设置多个
    morshoo.com
    wang@morshoo.com
   }
   notification_email_from server@morshoo.com #邮件的发送地址
   smtp_server 192.168.138.10 #smtp 地址
   smtp_connect_timeout 30 #连接smtp服务器超时的实际
   router_id LVS_DEVEL
}

#vrrp 实例定义部分
vrrp_instance VI_1 {
    state MASTER  #keepalived 的角色 MASTER 表示主机是主服务器 BACKUP表示是以备用服务器
    interface eth0 #指定监测的网络网卡
    virtual_router_id 51 #虚拟路由标示
    priority 100 #定义优先级 数字越大 优先级越高 MASTER的优先级必须大于BACKUP的优先级
    advert_int 1 #设定主备之间检查时间 单位s
    authentication {  #设定验证类型和密码
        auth_type PASS
        auth_pass 1111
    }
    virtual_ipaddress { #设定虚拟IP地址 可以设置多个 每行一个
        192.168.138.200
    }
}

#虚拟服务器部分
virtual_server 192.168.138.200 80 {
    delay_loop 6 #设定运行情况检查时间 单位s
    lb_algo rr #负载调度算法 rr即轮叫算法
    lb_kind DR #设置LVS负载机制 NAT TUN DR 三种模式可选
    nat_mask 255.255.255.0
    persistence_timeout 0  #会话保持时间
                            #有了这个会话保持功能 用户的请求会被一直分发到某个服务节点
                            #如果用户在动态页面50s内没有任何动作，那么后面就会被分发到其他节点
                            #如果用户一直有动作，不受50s限制

    protocol TCP  #协议

    #real server部分
    real_server 192.168.138.3 80 {
        weight 1  #服务节点权值，数字越大，权值越高
                  #权值的大小可以为不同性能的服务器分配不同的负载
                  #这样才能有效合理的利用服务器资源
        TCP_CHECK {  #状态检查部分    
          connect_timeout 3 #3s无响应超时                                                     
          nb_get_retry 3  #重试次数
          delay_before_retry 3   #重试间隔
          connect_port 80 #连接端口                                                    
        }  
    }

    #real server部分
    real_server 192.168.138.4 80 {
        weight 1  #服务节点权值，数字越大，权值越高
                  #权值的大小可以为不同性能的服务器分配不同的负载
                  #这样才能有效合理的利用服务器资源
        TCP_CHECK {  #状态检查部分    
          connect_timeout 3 #3s无响应超时                                                     
          nb_get_retry 3  #重试次数
          delay_before_retry 3   #重试间隔
          connect_port 80 #连接端口                                                    
        }  
    }
}
```


> backup机上的配置keepalived.conf:
```
#这里是全局定义部分
global_defs {
   notification_email {
    admin@morshoo.com   #设置报警邮件地址 每行一个 可以设置多个
    boss@morshoo.com
    cto@morshoo.com
   }
   notification_email_from server@morshoo.com #邮件的发送地址
   smtp_server 192.168.138.10 #smtp 地址
   smtp_connect_timeout 30 #连接smtp服务器超时的实际
   router_id LVS_DEVEL
}

#vrrp 实例定义部分
vrrp_instance VI_1 {
    state BACKUP  #keepalived 的角色 MASTER 表示主机是主服务器 BACKUP表示是以备用服务器
    interface eth0 #指定监测的网络网卡
    virtual_router_id 51 #虚拟路由标示
    priority 80 #定义优先级 数字越大 优先级越高 MASTER的优先级必须大于BACKUP的优先级
    advert_int 1 #设定主备之间检查时间 单位s
    authentication {  #设定验证类型和密码
        auth_type PASS
        auth_pass 1111
    }
    virtual_ipaddress { #设定虚拟IP地址 可以设置多个 每行一个
        192.168.138.200
    }
}

#虚拟服务器部分
virtual_server 192.168.138.200 80 {
    delay_loop 6 #设定运行情况检查时间 单位s
    lb_algo rr #负载调度算法 rr即轮叫算法
    lb_kind DR #设置LVS负载机制 NAT TUN DR 三种模式可选
    nat_mask 255.255.255.0
    persistence_timeout 0  #会话保持时间
                            #有了这个会话保持功能 用户的请求会被一直分发到某个服务节点
                            #如果用户在动态页面50s内没有任何动作，那么后面就会被分发到其他节点
                            #如果用户一直有动作，不受50s限制

    protocol TCP  #协议

    #real server部分
    real_server 192.168.138.3 80 {
        weight 1  #服务节点权值，数字越大，权值越高
                  #权值的大小可以为不同性能的服务器分配不同的负载
                  #这样才能有效合理的利用服务器资源
        TCP_CHECK {  #状态检查部分    
          connect_timeout 3 #3s无响应超时                                                     
          nb_get_retry 3  #重试次数
          delay_before_retry 3   #重试间隔
          connect_port 80 #连接端口                                                    
        }  
    }

    #real server部分
    real_server 192.168.138.4 80 {
        weight 1  #服务节点权值，数字越大，权值越高
                  #权值的大小可以为不同性能的服务器分配不同的负载
                  #这样才能有效合理的利用服务器资源
        TCP_CHECK {  #状态检查部分    
          connect_timeout 3 #3s无响应超时                                                     
          nb_get_retry 3  #重试次数
          delay_before_retry 3   #重试间隔
          connect_port 80 #连接端口                                                    
        }  
    }

```
}

* 把'etc/rc.d/init.d/keepalived'复制到'/etc/rc.d/init.d/'目录下
> cp etc/rc.d/init.d/keepalived  /etc/rc.d/init.d/
* 把'etc/sysconfig/keepalived' 复制到'/etc/sysconfig/'目录下
> cp /etc/sysconfig/keepalived  /etc/sysconfig/
* 把'sbin/keepalived' 复制到'/sbin/'目录下
> cp  sbin/keepalived /sbin/
* 把'etc/keepalived/keepalived.conf'复制到'/etc/keepalived/'目录下
> mkdir -p /etc/keepalived 

> cp etc/keepalived/keepalived.conf  /etc/keepalived/



* 日志位置修改:(原位置在/var/log/message)
> 先要修改 '/etc/sysconfig/keepalived' 文件，在最后一行 KEEPALIVED_OPTIONS="-D" 换成 KEEPALIVED_OPTIONS="-D -d -S 0"
> 然后在/etc/rsyslog.conf 后面加上一句:
```
#keepalived -S 0 
local0.*                              /usr/local/keepalived/logs/keepalived.log
```

* 建立新日志目录:
> mkdir -p /usr/local/keepalived/logs

* 重新启动系统日志:
> /etc/init.d/rsyslog restart

* 然后启动 主备 keepalived 和 服务节点的lvsrs:
> service keepalived start

> service lvsrs start

* 启动 real server 的nginx
> /usr/local/nginx/sbin/nginx

##第四步：测试
###负载均衡测试:	
> 测试脚本内容,test.sh:
```
#!/bin/bash
if [ ! -f "/root/backup/test.txt" ]
then
touch /root/backup/test.txt
fi

for((i=0;i<10;i++))
do
curl http://192.168.138.200 >>  /root/backup/test.txt
sleep 1
done
```

* 在备份服务器中运行test.sh
> sh test.sh

* 在服务器使用ipvsadm查看虚拟ip绑定状态

* 等待test.sh运行完出现如下结果
```
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
-> RemoteAddress:Port Forward Weight ActiveConn InActConn
TCP 192.168.138.200:http rr
-> 192.168.138.3:http Route 1 0 5 
-> 192.168.138.4:http Route 1 0 5 
```
> 每个都被分发了5次,即配置成功
### 高可用测试
> 此时192.168.138.200可以正常访问
* 关闭主机上的nginx(原文是关闭keepalived服务,即 service keepalived stop,为了更加真实的模拟环境,不关闭keepalived)
> service nginx stop

> 去查看备份机上的keepalived日志:
```
Feb 3 18:05:06 localhost Keepalived_vrrp[5549]: VRRP_Instance(VI_1) Transition to MASTER STATE
Feb 3 18:05:07 localhost Keepalived_vrrp[5549]: VRRP_Instance(VI_1) Entering MASTER STATE
Feb 3 18:05:07 localhost Keepalived_vrrp[5549]: VRRP_Instance(VI_1) setting protocol VIPs.
Feb 3 18:05:07 localhost Keepalived_vrrp[5549]: VRRP_Instance(VI_1) Sending gratuitous ARPs on eth0 for 192.168.138.200
Feb 3 18:05:07 localhost Keepalived_healthcheckers[5548]: Netlink reflector reports IP 192.168.138.200 added
Feb 3 18:05:12 localhost Keepalived_vrrp[5549]: VRRP_Instance(VI_1) Sending gratuitous ARPs on eth0 for 192.168.138.200
```

> 由上可知:备份机变成了master

> 192.168.138.200依然可以正常访问

* 再打开主机上的nginx服务:
> service nginx start

> 查看备份机上的日志信息:
```
b 3 18:08:09 localhost Keepalived_vrrp[5549]: VRRP_Instance(VI_1) Received higher prio advert
Feb 3 18:08:09 localhost Keepalived_vrrp[5549]: VRRP_Instance(VI_1) Entering BACKUP STATE
Feb 3 18:08:09 localhost Keepalived_vrrp[5549]: VRRP_Instance(VI_1) removing protocol VIPs.
Feb 3 18:08:09 localhost Keepalived_healthcheckers[5548]: Netlink reflector reports IP 192.168.138.200 removed
```
> 自动切换回BACKUP

# 以上为nginx的部署,如果不需要加上mysql的高可用可以到此为止了,下面是添加一个mysql的高可用

## 如果已按照nginx集群部署好,还要继续添加一个mysql的VIP的话;

* 先在lvsrs文件中添加一个vip,修改为如下内容:
```
#!/bin/bash
VIP_0=192.168.138.200
VIP_1=192.168.33.6
/etc/rc.d/init.d/functions
case "$1" in
start)
			   ifconfig lo:0 $VIP_0 netmask 255.255.255.255 broadcast $VIP_0 up
			   ifconfig lo:1 $VIP_1 netmask 255.255.255.255 broadcast $VIP_1 up
			   /sbin/route add -host $VIP_0 dev lo:0
			   /sbin/route add -host $VIP_1 dev lo:1
 
			   echo "1" >/proc/sys/net/ipv4/conf/lo/arp_ignore
			   echo "2" >/proc/sys/net/ipv4/conf/lo/arp_announce
			   echo "1" >/proc/sys/net/ipv4/conf/all/arp_ignore
			   echo "2" >/proc/sys/net/ipv4/conf/all/arp_announce
			   sysctl -p >/dev/null 2>&1
			   echo "RealServer Start OK"
			   ;;
stop)
			   ifconfig lo:0 down
			   ifconfig lo:1 down
			   /sbin/route del $VIP >/dev/null 2>&1
			   echo "0" >/proc/sys/net/ipv4/conf/lo/arp_ignore
			   echo "0" >/proc/sys/net/ipv4/conf/lo/arp_announce
			   echo "0" >/proc/sys/net/ipv4/conf/all/arp_ignore
			   echo "0" >/proc/sys/net/ipv4/conf/all/arp_announce
			   echo "RealServer Stoped"
			   ;;
*)
			   echo "Usage: $0 {start|stop}"
			   exit 1
esac
exit 0
```

* 然后去keepalived.conf中添加虚拟IP.
> master机配置:
```
#这里是全局定义部分
global_defs {
   #不发邮件的话可以把发邮件设置注释掉
   #notification_email {
   # admin@morshoo.com   #设置报警邮件地址 每行一个 可以设置多个
   # boss@morshoo.com
   # cto@morshoo.com
   #}
   #notification_email_from server@morshoo.com #邮件的发送地址
   #smtp_server 192.168.138.10 #smtp 地址
   #smtp_connect_timeout 30 #连接smtp服务器超时的实际
   router_id LVS_DEVEL
}

#vrrp 实例定义部分
vrrp_instance VI_1 {
    state MASTER  #keepalived 的角色 MASTER 表示主机是主服务器 BACKUP表示是以备用服务器
    interface eth0 #指定监测的网络网卡
    lvs_sync_daemon_inteface eth0
    virtual_router_id 51 #虚拟路由标示
    priority 100 #定义优先级 数字越大 优先级越高 MASTER的优先级必须大于BACKUP的优先级
    advert_int 1 #设定主备之间检查时间 单位s
    authentication {  #设定验证类型和密码
        auth_type PASS
        auth_pass 1111
    }
    virtual_ipaddress { #设定虚拟IP地址 可以设置多个 每行一个
        192.168.138.200
    }
}

#vrrp 实例定义部分
vrrp_instance VI_2 {
    state MASTER  #keepalived 的角色 MASTER 表示主机是主服务器 BACKUP表示是以备用服务器
    interface eth0 #指定监测的网络网卡
    lvs_sync_daemon_inteface eth0
    virtual_router_id 52 #虚拟路由标示
    priority 100 #定义优先级 数字越大 优先级越高 MASTER的优先级必须大于BACKUP的优先级
    advert_int 1 #设定主备之间检查时间 单位s
	nopreempt 
    authentication {  #设定验证类型和密码
        auth_type PASS
        auth_pass 2222
    }
    virtual_ipaddress { #设定虚拟IP地址 可以设置多个 每行一个
        192.168.33.6
    }
}
```

# master服务器部分的keepalived.conf
```
virtual_server 192.168.138.200 80 {
    delay_loop 6 #设定运行情况检查时间 单位s
    lb_algo rr #负载调度算法 rr即轮叫算法
    lb_kind DR #设置LVS负载机制 NAT TUN DR 三种模式可选
    nat_mask 255.255.255.0
    persistence_timeout 0  #会话保持时间
                            #有了这个会话保持功能 用户的请求会被一直分发到某个服务节点
                            #如果用户在动态页面50s内没有任何动作，那么后面就会被分发到其他节点
                            #如果用户一直有动作，不受50s限制

    protocol TCP  #协议

    #real server部分
    real_server 192.168.1.110 80 {
        weight 1  #服务节点权值，数字越大，权值越高
                  #权值的大小可以为不同性能的服务器分配不同的负载
                  #这样才能有效合理的利用服务器资源
        TCP_CHECK {  #状态检查部分    
          connect_timeout 3 #3s无响应超时                                                     
          nb_get_retry 3  #重试次数
          delay_before_retry 3   #重试间隔
          connect_port 80 #连接端口                                                    
        }  
    }

    #real server部分
    real_server 192.168.1.111 80 {
        weight 1  #服务节点权值，数字越大，权值越高
                  #权值的大小可以为不同性能的服务器分配不同的负载
                  #这样才能有效合理的利用服务器资源
        TCP_CHECK {  #状态检查部分    
          connect_timeout 3 #3s无响应超时                                                     
          nb_get_retry 3  #重试次数
          delay_before_retry 3   #重试间隔
          connect_port 80 #连接端口                                                    
        }  
    }
}
#mysql虚拟ip
 virtual_server 192.168.33.6 3306 {#修改为对应的VIP
         delay_loop 6
         lb_algo rr #lvs负载均衡算法
         lb_kind DR #lvs的转发模式
         #nat_mask 255.255.255.0
         #persistence_timeout 50
         protocol TCP
 
         real_server 192.168.1.110 3306 {#修改为对应的realserever
                 weight 2
                 TCP_CHECK {
                 connect_timeout 3
                 nb_get_retry 3
                 delay_before_retry 3
                 connect_port 3306
                 }
         }
 
         real_server 192.168.1.111 3306 {#修改为对应的realserver
                     weight 2
                     TCP_CHECK {
                     connect_timeout 3
                     nb_get_retry 3
                     delay_before_retry 3
                     connect_port 3306
                     }
         }
 
 }
```
> backup服务器配置keepalived.conf:
```
#这里是全局定义部分
        global_defs {
           #notification_email {
            #admin@morshoo.com   #设置报警邮件地址 每行一个 可以设置多个
            #boss@morshoo.com
            #cto@morshoo.com
           #}
           #notification_email_from server@morshoo.com #邮件的发送地址
           #smtp_server 192.168.138.10 #smtp 地址
           #smtp_connect_timeout 30 #连接smtp服务器超时的实际
           router_id LVS_DEVEL
        }
        
        #vrrp 实例定义部分
        vrrp_instance VI_1 {
            state BACKUP  #keepalived 的角色 MASTER 表示主机是主服务器 BACKUP表示是以备用服务器
            interface eth0 #指定监测的网络网卡
            lvs_sync_daemon_inteface eth0
            virtual_router_id 51 #虚拟路由标示
            priority 80 #定义优先级 数字越大 优先级越高 MASTER的优先级必须大于BACKUP的优先级
            advert_int 1 #设定主备之间检查时间 单位s
            authentication {  #设定验证类型和密码
                auth_type PASS
                auth_pass 1111
            }
            virtual_ipaddress { #设定虚拟IP地址 可以设置多个 每行一个
                192.168.138.200
            }
        }
        
        vrrp_instance VI_2 {
        	state BACKUP    #都修改成BACKUP
            interface eth0 #VIP要绑定到eth1上,是具体情况而定，填写具体的主机网卡名称
            lvs_sync_daemon_inteface eth0
            virtual_router_id 52
            priority 90 #对应备机的值要小于这个值
            advert_int 1
            authentication {
                auth_type PASS #备机上要与之一致
                auth_pass 2222 #备机上要与之一致
            }
            virtual_ipaddress {
                192.168.33.6
            }
        }
        
        
        #虚拟服务器部分
        virtual_server 192.168.138.200 80 {
            delay_loop 6 #设定运行情况检查时间 单位s
            lb_algo rr #负载调度算法 rr即轮叫算法
            lb_kind DR #设置LVS负载机制 NAT TUN DR 三种模式可选
            nat_mask 255.255.255.0
            persistence_timeout 0  #会话保持时间
                                    #有了这个会话保持功能 用户的请求会被一直分发到某个服务节点
                                    #如果用户在动态页面50s内没有任何动作，那么后面就会被分发到其他节点
                                    #如果用户一直有动作，不受50s限制
        
            protocol TCP  #协议
        
            #real server部分
            real_server 192.168.1.110 80 {
                weight 1  #服务节点权值，数字越大，权值越高
                          #权值的大小可以为不同性能的服务器分配不同的负载
                          #这样才能有效合理的利用服务器资源
                TCP_CHECK {  #状态检查部分    
                  connect_timeout 3 #3s无响应超时                                                     
                  nb_get_retry 3  #重试次数
                  delay_before_retry 3   #重试间隔
                  connect_port 80 #连接端口                                                    
                }  
            }
        
            #real server部分
            real_server 192.168.1.111 80 {
                weight 1  #服务节点权值，数字越大，权值越高
                          #权值的大小可以为不同性能的服务器分配不同的负载
                          #这样才能有效合理的利用服务器资源
                TCP_CHECK {  #状态检查部分    
                  connect_timeout 3 #3s无响应超时                                                     
                  nb_get_retry 3  #重试次数
                  delay_before_retry 3   #重试间隔
                  connect_port 80 #连接端口                                                    
                }  
            }
        }
        
        virtual_server 192.168.33.6 3306 { #修改为对应的VIP
                delay_loop 6
                lb_algo rr #lvs负载均衡算法
                lb_kind DR #lvs的转发模式
                #nat_mask 255.255.255.0
                #persistence_timeout 50
                protocol TCP
        
                real_server 192.168.1.110 3306 { #修改为对应的realserever
                        weight 2
                        TCP_CHECK {
                        connect_timeout 3
                        nb_get_retry 3
                        delay_before_retry 3
                        connect_port 3306
                        }
                }
        
                real_server 192.168.1.111 3306 { #修改为对应的realserver
                            weight 2
                            TCP_CHECK {
                            connect_timeout 3
                            nb_get_retry 3
                            delay_before_retry 3
                            connect_port 3306
                            }
                }
        
        }
```

* 然后重启lvsrs,keepalived:
> sevice lvsrs stop

> service lvsrs start

> service keepalived restart

* 可以分别断开两台mysql服务,通过第三方工具链接虚拟ip来链接mysql查看是否能正常连接,或者查看mysql当前链接主机名([命令自行百度](http://www.baidu.com))








