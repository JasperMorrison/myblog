---
layout: post
title: Android nougat ota tool
categories: Android-Framework
tags: Android nougat otatool
author: Jasper
---

* content
{:toc}

本文分析Android7（nougat）的otatool，以前大致分析过Android6的otatool，但是在具体的差分处理和img压缩方面没有搞清楚。Android7又增加了A/B升级模式，趁着这个机会，分析Android7 升级包的生成方法和过程。



## 概述

__Android6.*__

otatool能制作文件形式升级包、block升级包，以及基于两者的差分升级包。谷歌认证中，如果机子是64bit，内部存储器速率达到一定的水平时，则必须启用dm-verity，为了保证dm-verity的完整性，则必须启用block升级模式。  
升级原理：block升级把整个img替换，差分block升级则根据具体block差分情况，如果block没有变化则不更新，否则更新block。  
我曾经把Android6的otatool提取出来，支持从文件夹中制作block升级包，从两个包含系统各种镜像的文件夹中制作它们的block差分包。

__Android7.*__

在Andriod6的基础上加入了A/B升级模式，用于解决ota升级导致的系统问题，如果新系统不可用，会选择从原来的系统分区启动。Android6之前，如果新系统开不机，那么只能使用PC重刷，至少也需要从sdcard重刷。  
现在的目标是：要制作一个类似Adnroid6中实现的从文件夹中制作block升级包、A/B升级包以及基于它们的差分包。

## 准备工作

- 完全编译AOSP Android7.x源码（这里使用的是Android7.0_r1）.  
- 制作ota target包
- 制作各种升级包，了解制作过程和结果

具体做法见参考文献。

Android7.0_r1 aosp hikey常见问题：

- 提示找不到recovery。  
  把宏TARGET_NO_RECOVERY设置为false(device/linaro/hikey/BoardConfig.mk)。
- 制作ota包时提示找不到recovery.fstab，导致block包制作失败。  
  修改otatools中的函数LoadRecoveryFSTab，让其从RECOVERY/RAMDISK/fstab.hikey获得fstab
- otatools从fstab中找不到boot分区。
  那就添加一个，复制system那条，把by-name后面改成`boot /boot emmc defaults defaults`

## OTATools参数说明

如不特别声明，源码来自build/tools/releasetools下。

```python
'''
Usage:  ota_from_target_files [flags] input_target_files output_ota_package

  -k (--package_key) <key>
      指定一个ota包签名的key，否则采用默认的key，来自source-target。

  -i  (--incremental_from)  <file>
      指明从哪里制作差分包

  --full_radio
      包含完整的img，

  --full_bootloader
      差分包时包含完整的bootloader镜像

  -v  (--verify)
      差分包时校验镜像内文件

  -o  (--oem_settings)  <file>
      使用文件指定OEM分区内的OEM properties

  --oem_no_mount
      如果有 -o 选项，则表示OEM properties file没有具体存放的分区

  -w  (--wipe_user_data)
      指定OTA包能清空用户数据

  -n  (--no_prereq)
      忽略升级况timestamp校验，这个校验语句在update script开始的地方。一般用于开发模式，
      开发者期望回退版本。

  --downgrade
      故意制作一个差分包，从一个新版本降到一个旧版本（是通过timestamp判断的）。在metadata file中，
      "ota-downgrade=yes" "ota-wipe=yes"，并默认使用source target中的update-binary，除非 --binary被指定。

  -e  (--extra_script)  <file>
      在update script的尾部追加<file>中的内容

  -a  (--aslr_mode)  <on|off>
      Specify whether to turn on ASLR for the package (on by default).
      空间格局随机化

  -2  (--two_step)
      两个步骤升级：先升级recovery，然后重启，使用新的recovery升级系统。

  --block
      制作block包

  -b  (--binary)  <file>
      指定 update-binary，只用于开发模式。

  -t  (--worker_threads) <int>
      otatools的工作线程，(defaults to 3).

  --stash_threshold <float>
      指定内存使用阈值（threshold）

  --gen_verify
      生成的OTA包会对分区进行校验，具体是哪些分区？

  --log_diff <file>
      当指定选项 -i 时，获得source zip与target zip的差分信息。
'''
```

## OTATools的工作过程

过程来自main函数

- 解析命令行参数
- 打开sorce/target zip => input_zip，如果是差分包 input_zip = target zip，否则不进行区分。
- 解析文件META/misc_info.txt，先把内容放在一个字典OPTIONS.info_dict中。
- 关闭input_zip，注意关闭的方法，考虑了一个bug。
- 如果ab_update == true（从字典中获得）
  - 如果是制作差分包
    - 保存刚才的input_zip为target_zip(这里没有保存，只是默认args[0])，-i 指定的zip为source_zip，保存OPTIONS.info_dict 为OPTIONS.target_info_dict
    - 解析source_zip中的META/misc_info.txt，保存到OPTIONS.source_info_dict，关闭source_zip.
  - WriteABOTAPackageWithBrilloScript(target_file=args[0],output_file=args[1],source_file=OPTIONS.incremental_source)
  - return，注意：如果是ab_update，这里就return了。
- 追加的升级脚本：OPTIONS.extra_script
- 解压input_zip到OPTIONS.target_tmp
- 解析文件misc_info.txt 保存到OPTIONS.info_dict
- 决定使用哪个升级工具，保存到OPTIONS.device_specific（META/releasetools.py或者由OPTIONS.info_dict的tool_extensions指定）  
  注意：这个device_specific，默认tool_extensions指向一个没有升级工具的目录，至少MTK 6.0中并没有使用它，但MTK 7.0添加了部分函数。
- input_zip中必须包含一个recovery
- 决定使用哪个签名的key
- 指定output_zip为临时文件（要签名的情况下）
- 获取OPTIONS.cache_size，可以是空
- OTA包的类型是什么？
  - 校验包：WriteVerifyPackage： 对input_zip中的boot/recovery/system/vender镜像生成校验信息
  - Full 升级包：WriteFullOTAPackage(input_zip, output_zip)
  - 差分升级包： OPTIONS.target_info_dict = OPTIONS.info_dict, 解压source_zip并解析OPTIONS.source_info_dict
    - WriteIncrementalOTAPackage(input_zip, source_zip, output_zip)
    - 保存差分信息target_files_diff.recursiveDiff
- 关闭output_zip
- 签名OTA包

## A/B升级包

__如何使能A/B Update?__

[A/B Update implementation](https://source.android.com/devices/tech/ota/ab_updates.html#implementation)

很显然，AOSP Android7.0并没有默认添加这个功能。

说明：

- 不需要recovery分区，自然就没有recovery.img
- 需要bootloader、kernel和Android同时支持
- 需要一对特殊的校验key，RSA格式
- fstab需要特殊标记
- 制作ota的命令是一样的，类似制作Full 文件升级包一样，除了-i不加额外选项
- 其它的很多很多

__检查是否开启A/B Update__

查找 ro.build.ab_update属性

__关于A/B Update__

数据是分块的，在软件层面上叫payload。这些payload可以下载，分别进行更新。更新动作在后台进行，这个后台策略由很多因素参与，比如用户的活动，是否在充电，电池电量等等。升级动作也随时可以被策略中断，无故重启也会中断升级动作。  
一个payload包含metadata和与其关联的 extra data。Metadata决定了data的具体操作方式。升级动作可以是写一个分区，读一个旧的分区进行比对来做差分升级

Step1~Step2：设置current slot和target slot的状态
Step3~Step4：下载metadata，并根据meatadata的信息下载extra data放到内存中。这个过程占据了升级的大部分时间，因为它可能需要下载大量的数据。当然，它也是同样是可以被中断的。  
Step5~Step6：校验整个分区并开始升级。(Post-install)
Step7: Call setActiveBootSlot() for new slot.

Post-install需要注意的地方：  

1. 使用单独的目录执行升级脚本(或者是升级程序)
2. 提供一个单独的分区执行升级脚本会更方便
3. 升级脚本受到Selinux权限限制

__脚本源码分析__

首先，这里的target zip不包含ab_update信息，所以它不会被执行，我们关注它是怎么制作payload和产生的升级脚本情况。

```python
WriteABOTAPackageWithBrilloScript(
        target_file=args[0],
        output_file=args[1],
        source_file=OPTIONS.incremental_source) //如果不是差分升级，这个是空
```

- 设置OTA包签名key
- 制作RSAkey
- output_zip指向临时文件
- 设置metadata
- 1.Generate payload  
  payload_file: tempfile
  brillo_update_payload generate --payload payload_file --target_image target_file [ --source_image source_file ]
- 2. Generate hashes of the payload and metadata files  
  metadata_sig_file  payload_sig_file : tempfile
  bash brillo_update_payload --unsigned_payload payload_file --signature_size 256 --metadata_hash_file metadata_sig_file --payload_hash_file payload_sig_file
- 3. Sign the hashes and insert them back into the payload file.  
  对上一步生成的两个sig_file进行签名
  把签名后的两个sig_file添加到payload file得到signed_payload_file，即签名后的payload file
- 获得签名后的payload file 的properties
- 把签过名的payloa file和它的properties一起加到output_zip中

整个过程涉及两个工具的使用：1.brillo_update_payload；2.openssl。

1. system/update_engine/scripts/brillo_update_payload
2. openssl在out/host可以找得到，这里使用的是linux自带的openssl

### brillo_update_payload

system/update_engine/scripts/brillo_update_payload  
内部调用到delta_generator
从system/update_engine可知：delta_generator主要程序在system/update_engine/payload_generator下，依赖其它库。

介于默认不支持这个功能，现在暂时不分析了。

## Full升级包

WriteFullOTAPackage

- 获得recovery.img，如果是2-step升级方式，则需要使用到bcb-dev分区。
- 计算或者获得fingerprint
- 引用vendor自定义的函数device_specific.FullOTA_InstallBegin()
- 获得selinux_fc(in Android7 is file_contexts.bin)，获得recovery mount point，获得META/filesystem_config.txt（用户信息，权限，selinux等）
- block升级包还是文件升级包？下面只考虑block升级包
- 获得systemimg
- 重置文件map
- 获得差分数据
- 将差分信息写入升级脚本
- 获得bootimg，复制数据并更新升级脚本
- 用类似处理systemimg的方式处理vendorimg，如果有的话
- 引用vendor自定义的函数device_specific.FullOTA_InstallEnd()
- 收尾工作

分析full block ota的核心源码：

```python
if block_based:
  # Full OTA is done as an "incremental" against an empty source
  # image.  This has the effect of writing new data from the package
  # to the entire partition, but lets us reuse the updater code that
  # writes incrementals to do it.
  system_tgt = GetImage("system", OPTIONS.input_tmp, OPTIONS.info_dict)
  system_tgt.ResetFileMap()
  system_diff = common.BlockDifference("system", system_tgt, src=None)
  system_diff.WriteScript(script, output_zip)
```

### GetImage

```python
def GetImage(which, tmpdir, info_dict):
  # Return an image object (suitable for passing to BlockImageDiff)
  # for the 'which' partition (most be "system" or "vendor").  If a
  # prebuilt image and file map are found in tmpdir they are used,
  # otherwise they are reconstructed from the individual files.

  # 这个解释很明了，返回一个image object给BlockImageDiff用的，一般是system/vendor两个分区，
  # 在input_zip解压后的temp文件夹中应该包含对应的image和file map两个文件，
  # 否则，脚本会尝试从分离的大量文件中重新制作对应的image和file map文件。

  assert which in ("system", "vendor")

  path = os.path.join(tmpdir, "IMAGES", which + ".img")
  mappath = os.path.join(tmpdir, "IMAGES", which + ".map")
  if os.path.exists(path) and os.path.exists(mappath):
    print "using %s.img from target-files" % (which,)
    # This is a 'new' target-files, which already has the image in it.

  else:
    print "building %s.img from target-files" % (which,)

    # This is an 'old' target-files, which does not contain images
    # already built.  Build them.

    mappath = tempfile.mkstemp()[1]
    OPTIONS.tempfiles.append(mappath)

    import add_img_to_target_files
    if which == "system":
    #我们应当关注一下这里的制作方式，简单的，在make_ext4fs加上-B file.map参数可以获得对应的file map信息
      path = add_img_to_target_files.BuildSystem(
          tmpdir, info_dict, block_list=mappath)
    elif which == "vendor":
      path = add_img_to_target_files.BuildVendor(
          tmpdir, info_dict, block_list=mappath)

  # Bug: http://b/20939131
  # In ext4 filesystems, block 0 might be changed even being mounted
  # R/O. We add it to clobbered_blocks so that it will be written to the
  # target unconditionally. Note that they are still part of care_map.
  clobbered_blocks = "0"
  # 我理解的意思是，ext4文件系统镜像，mount的时候，第一个block总是被修改，所以我们不使用这个block，仅仅当作一个占位空间。
  # 脚本的做法是，对clobbered_blocks指定的block，总是写到target中。见下一节的说明

  return sparse_img.SparseImage(path, mappath, clobbered_blocks)
```

### SparseImage

一个system.img的二进制头部数据：

```
od -tx4 -w32 system.img | head -n 4                           
0000000 ed26ff3a 00000001 000c001c 00001000 000e0000 000016da 00000000 0000cac1
0000040 00000001 0000100c 00000000 00000000 00000000 00000000 00000000 00000000
0000100 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
```

前28bit(file header)：ed26ff3a 00000001 000c001c 00001000 000e0000 000016da 00000000
接下来的12bit(chunk header)：0000cac1 00000001 0000100c

一个system.img的大致文件结构是这样的：

|header |
|chunk|
||chunk header
||chunk data
|chunk|
||chunk header
||chunk data
|......|......

为了方便解析unsigned short，也把每2字节数据打印出来：

```
od -tx2 -w32 system.img | head -n 4
0000000 ff3a ed26 0001 0000 001c 000c 1000 0000 0000 000e 16da 0000 0000 0000 cac1 0000
0000040 0001 0000 100c 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000
0000100 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000
```

```python
"""Wraps a sparse image file into an image object.

  Wraps a sparse image file (and optional file map and clobbered_blocks) into
  an image object suitable for passing to BlockImageDiff. file_map contains
  the mapping between files and their blocks. clobbered_blocks contains the set
  of blocks that should be always written to the target regardless of the old
  contents (i.e. copying instead of patching). clobbered_blocks should be in
  the form of a string like "0" or "0 1-5 8".
  """

  def __init__(self, simg_fn, file_map_fn=None, clobbered_blocks=None,
               mode="rb", build_map=True):
    self.simg_f = f = open(simg_fn, mode)

    header_bin = f.read(28)
    header = struct.unpack("<I4H4I", header_bin)
    # 这里是把buffer数据格式化，"<I4H4I"就是格式方式，得到的数据放入一个List中。
    # < : 小端序
    # I ： 1个int 1*4 = 4
    # 4H ： 4个unsigned short 4*2 = 8
    # 4I ： 4个int 1*4 = 4
    # 9个数据，共28个bit。

    # 1个int
    magic = header[0]
    # 4个unsigned short
    major_version = header[1]
    minor_version = header[2]
    file_hdr_sz = header[3]    
    chunk_hdr_sz = header[4]
    # 4个int
    self.blocksize = blk_sz = header[5]
    self.total_blocks = total_blks = header[6]
    self.total_chunks = total_chunks = header[7]
    # 4个中的最后一个int没有使用，预留的。

    if magic != 0xED26FF3A:
      raise ValueError("Magic should be 0xED26FF3A but is 0x%08X" % (magic,))
    if major_version != 1 or minor_version != 0:
      raise ValueError("I know about version 1.0, but this is version %u.%u" %
                       (major_version, minor_version))
    if file_hdr_sz != 28:
      raise ValueError("File header size was expected to be 28, but is %u." %
                       (file_hdr_sz,))
    if chunk_hdr_sz != 12:
      raise ValueError("Chunk header size was expected to be 12, but is %u." %
                       (chunk_hdr_sz,))

    print("Total of %u %u-byte output blocks in %u input chunks."
          % (total_blks, blk_sz, total_chunks))

    if not build_map:
      return

    pos = 0   # in blocks，对于整个system.img而言，pos表示第几个block，从0开始
    care_data = [] # 关心的list
    self.offset_map = offset_map = []
    self.clobbered_blocks = rangelib.RangeSet(data=clobbered_blocks)

    for i in range(total_chunks): #遍历所有的chunk
      header_bin = f.read(12)
      header = struct.unpack("<2H2I", header_bin)
      chunk_type = header[0]
      chunk_sz = header[2] # 表示data中包含block的个数
      total_sz = header[3] #整个chunk的大小
      data_sz = total_sz - 12 #chunk中data区大小

      if chunk_type == 0xCAC1:
        if data_sz != (chunk_sz * blk_sz):
          raise ValueError(
              "Raw chunk input size (%u) does not match output size (%u)" %
              (data_sz, chunk_sz * blk_sz))
        else:
          # 记录一个pos的范围
          care_data.append(pos)
          care_data.append(pos + chunk_sz)
          # 把一个元组加入list中，元组信息(block的位置, block的个数, 文件偏移量, 空)
          offset_map.append((pos, chunk_sz, f.tell(), None))
          pos += chunk_sz # pos位置往后移动
          f.seek(data_sz, os.SEEK_CUR) # 改变文件偏移量，移到下一个chunk

      elif chunk_type == 0xCAC2:
        fill_data = f.read(4)
        care_data.append(pos)
        care_data.append(pos + chunk_sz)
        offset_map.append((pos, chunk_sz, None, fill_data))
        pos += chunk_sz
        #从上面的意思可见：在第pos个block开始的chunk_sz个block填充f.read(4)的内容
        #f通过read函数自动往后移动4个字节

      elif chunk_type == 0xCAC3:
        if data_sz != 0:
          raise ValueError("Don't care chunk input size is non-zero (%u)" %
                           (data_sz))
        else:
          pos += chunk_sz #只是一个简单的chunk头，略过。

      elif chunk_type == 0xCAC4:
        raise ValueError("CRC32 chunks are not supported")

      else:
        raise ValueError("Unknown chunk type 0x%04X not supported" %
                         (chunk_type,))

    #到此，得到两个信息：1. 保存了block范围的care_data； 2.保存了大量元组信息的offset_map。

    #这个功能是明确的，把多个连续的子空间变成一个大空间： 1-2 2-4 4-10 = 1-10
    self.care_map = rangelib.RangeSet(care_data)
    #取出所有的pos，放到一个list中。
    self.offset_index = [i[0] for i in offset_map]

    # Bug: 20881595
    # Introduce extended blocks as a workaround for the bug. dm-verity may
    # touch blocks that are not in the care_map due to block device
    # read-ahead. It will fail if such blocks contain non-zeroes. We zero out
    # the extended blocks explicitly to avoid dm-verity failures. 512 blocks
    # are the maximum read-ahead we configure for dm-verity block devices.
    extended = self.care_map.extend(512) #子空间前后扩展512 blocks
    all_blocks = rangelib.RangeSet(data=(0, self.total_blocks)) # 获得有效范围
    extended = extended.intersect(all_blocks).subtract(self.care_map) # && ||，得到具体需要拓展的blocks
    self.extended = extended
    #上面的代码考虑了一个bug，对于支持dm-verity的设备，在校验system.img的时候，有512个block的预读数据，我们需要将其置0.

    if file_map_fn:
      #如果我们前面给了一个.map文件
      #这样，就区分空和非空block，分别标志为__ZERO和__NONZERO，并把clobbered_blocks标志为__COPY
      self.LoadFileBlockMap(file_map_fn, self.clobbered_blocks)
    else:
      #如果没有，如果我们不做差分包，.map文件不是必须的，后面会看到ResetFileMap函数，否认了LoadFileBlockMap的工作。
      #这样，就把关心的数据标志为"__DATA"
      self.file_map = {"__DATA": self.care_map}
```

__RangeSet__

```python
class RangeSet(object):
  """A RangeSet represents a set of nonoverlapping ranges on the
  integers (ie, a set of integers, but efficient when the set contains
  lots of runs."""
  # 代表一个不重叠的数据集合，也就是去重。

  def __init__(self, data=None):
    self.monotonic = False
    if isinstance(data, str): # str的去重
      self._parse_internal(data)
    elif data:
      assert len(data) % 2 == 0
      self.data = tuple(self._remove_pairs(data)) #元组的去重，多个连续的空间拼成一个大空间。yield
      #检查data递增性
      self.monotonic = all(x < y for x, y in zip(self.data, self.data[1:]))
    else:
      self.data = ()
```

__LoadFileBlockMap__

.map 文件是类似这样的，指定了一个文件所在的blocks：  
/system/priv-app/MediaProvider/MediaProvider.apk 40027-40064

这个函数的作用是将.map文件的(filename,ranges)保存到file_map中，然后对剩余的空间判定空和非空数据，分别标志为__ZERO和__NONZERO，并将clobbered_blocks标志为__COPY，也保存在file_map字典中。
下面是详细解释：

```python
def LoadFileBlockMap(self, fn, clobbered_blocks):
  remaining = self.care_map
  self.file_map = out = {}

  with open(fn) as f:
    for line in f:
      fn, ranges = line.split(None, 1) #得到文件path和它的block范围
      ranges = rangelib.RangeSet.parse(ranges) #返回一个RangeSet对象，包含整理过的block范围信息
      out[fn] = ranges #把两者保存到字典 file_map
      assert ranges.size() == ranges.intersect(remaining).size() #校验空间是否存在care_map中

      # Currently we assume that blocks in clobbered_blocks are not part of
      # any file.
      assert not clobbered_blocks.overlaps(ranges)
      remaining = remaining.subtract(ranges) #计算剩下的空间

  remaining = remaining.subtract(clobbered_blocks) #先把必须填充的空间去掉

  # For all the remaining blocks in the care_map (ie, those that
  # aren't part of the data for any file nor part of the clobbered_blocks),
  # divide them into blocks that are all zero and blocks that aren't.
  # (Zero blocks are handled specially because (1) there are usually
  # a lot of them and (2) bsdiff handles files with long sequences of
  # repeated bytes especially poorly.)
  # 剩下的空间是不包含任何文件的，也不是必须填充的空间。
  # 我们把它们分离成空和非空，空的空间是特殊的，因为：1.它们很多；2.bsdiff在处理文件的时候，会包含很多重复的字节，即使这样做很傻。

  zero_blocks = []
  nonzero_blocks = []
  reference = '\0' * self.blocksize  # 创建blocksize个'\0'，保存成字符串

  # Workaround for bug 23227672. For squashfs, we don't have a system.map. So
  # the whole system image will be treated as a single file. But for some
  # unknown bug, the updater will be killed due to OOM when writing back the
  # patched image to flash (observed on lenok-userdebug MEA49). Prior to
  # getting a real fix, we evenly divide the non-zero blocks into smaller
  # groups (currently 1024 blocks or 4MB per group).
  # Bug: 23227672
  MAX_BLOCKS_PER_GROUP = 1024
  nonzero_groups = []

  f = self.simg_f
  for s, e in remaining: # 遍历block区间，得到开始和结尾
    for b in range(s, e): # 对于每一个block
      idx = bisect.bisect_right(self.offset_index, b) - 1 # 是第一个block？
      chunk_start, _, filepos, fill_data = self.offset_map[idx] # 取出block字典信息
      if filepos is not None: #有数据的
        filepos += (b-chunk_start) * self.blocksize #文件偏移量后移
        f.seek(filepos, os.SEEK_SET) #文件指针后移
        data = f.read(self.blocksize) #读取文件数据(从system.img中)，为什么要读取数据，后面你又不用？？？
      else: #没有数据，或者是填充数据
        if fill_data == reference[:4]:   # fill with all zeros，如果填充数据是'\0'
          data = reference
        else:
          data = None #不理会填充数据是什么

      if data == reference:
        zero_blocks.append(b)
        zero_blocks.append(b+1)
      else:
        nonzero_blocks.append(b)
        nonzero_blocks.append(b+1)

        if len(nonzero_blocks) >= MAX_BLOCKS_PER_GROUP:
          nonzero_groups.append(nonzero_blocks)
          # Clear the list.
          nonzero_blocks = []

  if nonzero_blocks:
    nonzero_groups.append(nonzero_blocks)
    nonzero_blocks = []

  assert zero_blocks or nonzero_groups or clobbered_blocks

  if zero_blocks:
    out["__ZERO"] = rangelib.RangeSet(data=zero_blocks)
  if nonzero_groups:
    for i, blocks in enumerate(nonzero_groups):
      out["__NONZERO-%d" % i] = rangelib.RangeSet(data=blocks)
  if clobbered_blocks:
    out["__COPY"] = clobbered_blocks
```

到此getImage函数就完成了。

### BlockDifference

system_diff = common.BlockDifference("system", system_tgt, src=None)  

```python
class BlockDifference(object):
  def __init__(self, partition, tgt, src=None, check_first_block=False,
               version=None, disable_imgdiff=False):
    self.tgt = tgt
    self.src = src
    self.partition = partition
    self.check_first_block = check_first_block
    self.disable_imgdiff = disable_imgdiff

    if version is None:
      version = 1
      if OPTIONS.info_dict:
        version = max(
            int(i) for i in
            OPTIONS.info_dict.get("blockimgdiff_versions", "1").split(","))
    self.version = version

    # 获得一个BlockImageDiff对象，记住这里传入的参数，后面的Compute函数需要用到
    b = blockimgdiff.BlockImageDiff(tgt, src, threads=OPTIONS.worker_threads,
                                    version=self.version,
                                    disable_imgdiff=self.disable_imgdiff)
    tmpdir = tempfile.mkdtemp()
    OPTIONS.tempfiles.append(tmpdir)
    self.path = os.path.join(tmpdir, partition)

    #调用BlockImageDiff对象的Compute方法，核心方法在这。
    b.Compute(self.path)

    self._required_cache = b.max_stashed_size
    self.touched_src_ranges = b.touched_src_ranges
    self.touched_src_sha1 = b.touched_src_sha1

    if src is None:
      _, self.device = GetTypeAndDevice("/" + partition, OPTIONS.info_dict)
    else:
      _, self.device = GetTypeAndDevice("/" + partition,
                                        OPTIONS.source_info_dict)
```

### BlockImageDiff.Compute

```python
def Compute(self, prefix):  # prefix 是一个临时文件，用于存放计算结果
  # When looking for a source file to use as the diff input for a
  # target file, we try:
  #   1) an exact path match if available, otherwise
  #   2) a exact basename match if available, otherwise
  #   3) a basename match after all runs of digits are replaced by
  #      "#" if available, otherwise
  #   4) we have no source for this target.
  self.AbbreviateSourceNames() # 对target_src的file_map提取所有的key，将文件名保存起来
  self.FindTransfers()
  # 对file_map中的标志为filename/__ZERO/__NONZERO/__COPY的信息进行转换
  # 非filename: 直接创建一个Transfer
  # filename：将标志为'diff'，并区分文件有没有数字，然后创建对应的Transfer，如果文件过大，将被分为多个Transfer。具体依照cache分区的大小。
  # 不是标志的target信息，被标志为'new'来创建Transfer对象
  # 将上面创建的Transfer对象保存到transfers列表中。

  # Find the ordering dependencies among transfers (this is O(n^2)
  # in the number of transfers).
  self.GenerateDigraph() # 对生成的transfers列表进行排序，这样的好处是方便数据顺序写入。

  # 搞不懂下面这几个是什么鬼算法，但是至少知道，它是优化transfers列表的。
  # Find a sequence of transfers that satisfies as many ordering
  # dependencies as possible (heuristically).
  self.FindVertexSequence()  
  # Fix up the ordering dependencies that the sequence didn't
  # satisfy.
  if self.version == 1:
    self.RemoveBackwardEdges()
  else:
    self.ReverseBackwardEdges()
    self.ImproveVertexSequence()

  # Ensure the runtime stash size is under the limit.
  if self.version >= 2 and common.OPTIONS.cache_size is not None:
    self.ReviseStashSize()

  # Double-check our work.
  self.AssertSequenceGood()

  # 对transfers进行分类计算和处理
  # 对于zip格式的文件，如apk、jar、zip，采用imgdiff工具，对于其它文件，采用bsdiff工具。
  # 分别给.patch.dat 和 .new.dat写入对应的数据。
  # 对于full非差分升级包，.patch.dat为空。
  self.ComputePatches(prefix)
  self.WriteTransfers(prefix)
```  

## 差分升级包

同样的，只关心block升级方式：  
WriteIncrementalOTAPackage -> return WriteBlockIncrementalOTAPackage(target_zip, source_zip, output_zip)

system_diff = common.BlockDifference("system", system_tgt, src=None)  
依然是主要函数，src不等于None就是制作差分包。transfers生成和优化，差分文件的写入等在上面的内容已经涉及。这里不做记录。

## 总结

Android7的升级包制作方法与Android6除了插入了A/B升级包制作方法外，其它方面基本是一样的。不同的是，Android7支持vendor定制脚本，在begin和end的时候做一些个性化工作。比如MTK android7就利用了end部分。

A/B升级包因为非默认，需要设计bootloader、driver、HAL以及Android层面的实现。暂时还没有产品实现这个功能，涉及的update-engin也比较难理解。就展示搁置了。

block升级包依然是核心，full block升级包是我们目前使用的升级包，依赖单个ROM就可以制作。对于system/vender，原理是读取image，解析header/chunk，将信息写入care_map，数据标志为__DATA，全部当作data写入升级包。其它额外工作不总结了。

差分升级包，在block升级包的基础上，还需要另一个source ROM，同样的方式解析image文件得到care_map，再根据file_map获得文件与block的映射关系，然后包含数据分类的transfer列表，根据transfer列表完成各类数据的写入。其它额外工作不总结了。

## 参考文献

[Android OTA Updates](https://source.android.com/devices/tech/ota/index.html)  
[python zip函数](www.cnblogs.com/frydsh/archive/2012/07/10/2585370.html)
[python 推导式](http://www.2cto.com/kf/201412/363165.html)   
