---
layout: post
title: 百问Kernel(2)：syscall如何找到sysfs的show/store函数
categories: Kernel 
tags: Linux sysfs kobject
author: Jasper
---

* content
{:toc}

根据常规的驱动开发模式，syscall会调用到device自定义的file_operations，从而，可以让我们响应系统调用read/write。对于sysfs，syscall又是如何找到sysfs_ops呢？




```c
struct sysfs_ops {
	ssize_t	(*show)(struct kobject *, struct attribute *, char *);
	ssize_t	(*store)(struct kobject *, struct attribute *, const char *, size_t);
};
```

> 基于 kobject-example.c

# 关键字

1. syscall
2. sysfs
3. sysfs_ops
4. kobject
5. attribute

# kobject注册到sysfs

```c
example_kobj = kobject_create_and_add("kobject_example", kernel_kobj);
retval = sysfs_create_group(example_kobj, &attr_group);
```

kobject_create_and_add : 在sysfs文件系统路径 sys/kernel 下面创建kobject_example目录。

sysfs_create_group : 将attribute组注册到sysfs的节点中。

![](/images/Linux/002-kobject-sample-add-ops-01.png)

上面的调试结果看到，`ops=&sysfs_file_kfops_rw`，先记住这个局部变量ops，以及传递进来的attribute group中的某个attr 名为 foo。

```c
kn = __kernfs_create_file(parent, attr->name, mode & 0777, uid, gid,
				size, ops, (void *)attr, ns, key);
```

上面代码表示开始创建具体的文件，也就是 `/sys/kernel/foo`.

![](/images/Linux/002-kobject-sample-add-ops-02.png)

上述调试结果表明，sysfs其实是利用了kernfs来创建文件节点，并将ops和priv记录在节点中。

> kernfs本来是sysfs的东西，后来由于需要拆分独立sysfs的功能而创建的伪文件系统，kernfs_node就是其文件树中的一个节点。

# syscall-read/write

不管怎样，kernfs_node总是要跟vfs的inode建立连接的，如此，用户才能透过vfs找到kernfs_node，最终调用sysfs_ops。

这里不做展开，将在下一问《sysfs怎么与vfs建立关联》中解答这个问题，结果就是：vfs的read/write会调用到前面定义的ops，即 sysfs_file_kfops_rw。

```c
static const struct kernfs_ops sysfs_file_kfops_rw = {
	.seq_show	= sysfs_kf_seq_show,
	.write		= sysfs_kf_write,
};
```

# sysfs_ops

```c
static int sysfs_kf_seq_show(struct seq_file *sf, void *v)
{
	struct kernfs_open_file *of = sf->private;
	struct kobject *kobj = of->kn->parent->priv;
	const struct sysfs_ops *ops = sysfs_file_ops(of->kn);

	if (ops->show) {
		count = ops->show(kobj, of->kn->priv, buf);
		if (count < 0)
			return count;
	}
}
```

通过kernfs_node 找到 sysfs_ops，及其 priv 找到attribute，这两个正是前面传递给的 `__kernfs_create_file` 参数。

```c
static ssize_t sysfs_kf_write(struct kernfs_open_file *of, char *buf,
			      size_t count, loff_t pos)
{
	const struct sysfs_ops *ops = sysfs_file_ops(of->kn);
	struct kobject *kobj = of->kn->parent->priv;

	if (!count)
		return 0;

	return ops->store(kobj, of->kn->priv, buf, count);
}
```

过程与调用show相同。

# 参考

更多信息参考另一问：《sysfs怎么与vfs建立关联》。
