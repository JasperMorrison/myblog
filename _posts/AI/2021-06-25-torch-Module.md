---
layout: post
title: torch nn.Module
categories: "AI"
tags: AI torch pytorch nn.Module
author: Jasper
---

* content
{:toc}

从代码的角度熟悉nn.Module，跳过苦涩难懂的文档。Module的代码非常简单，比网上各种文档简单多了。




# 内置方法

python重载：

`__dict__`：获取对象属性  
`__setattr__`： 设置对象属性，响应python setattr(object)函数， 同时，obj.my\_attr = "value" 也同理，保存到`__dict__`  
`__dir__`：获取对象属性和方法，响应python dir(object)函数  
`__getattr__`：响应python getattr(object)函数  
`__repr__`：响应print()函数，输出“类名+object at+内存地址”信息  
`__iadd__`：响应算术运算符 `+`  


Module自定义：

`__setstate__`：设置Module的状态，已知在JIT.trace时有用到  

# 构建Module

```python
import torch.nn as nn
import torch.nn.functional as F

class Model(nn.Module):
    def __init__(self):
        super(Model, self).__init__()
        self.conv1 = nn.Conv2d(1, 20, 5)
        self.conv2 = nn.Conv2d(20, 20, 5)

    def forward(self, x):
        x = F.relu(self.conv1(x))
        return F.relu(self.conv2(x))
```

`__init__`： 将conv1和conv2设置为属性，见上方`__setattr__`的说明

除此之外，super中构建：

```python
    def __init__(self):
        """
        Initializes internal Module state, shared by both nn.Module and ScriptModule.
        """
        torch._C._log_api_usage_once("python.nn_module")

        self.training = True
        self._parameters = OrderedDict()
        self._buffers = OrderedDict()
        self._non_persistent_buffers_set = set()
        self._backward_hooks = OrderedDict()
        self._is_full_backward_hook = None
        self._forward_hooks = OrderedDict()
        self._forward_pre_hooks = OrderedDict()
        self._state_dict_hooks = OrderedDict()
        self._load_state_dict_pre_hooks = OrderedDict()
        self._modules = OrderedDict()
```

先记住这些属性，在创建Module对象时，它们仅仅是初始化。

# 容器

`modules/container.py`

容器是用来存放算子的东西，容器也是一个Module对象。  
算子也是一个Module对象，所以，容器可以称为：
1. 算子的容器；
2. Module的容器；
3. Module的Module

容器有几种：  
1. Sequential
2. ModuleList
3. ......

## Sequential的构建

```python
class Sequential(Module):
    def __init__(self, *args):
        super(Sequential, self).__init__()
        if len(args) == 1 and isinstance(args[0], OrderedDict):
            for key, module in args[0].items():
                self.add_module(key, module)
        else:
            for idx, module in enumerate(args):
                self.add_module(str(idx), module)

    @_copy_to_script_wrapper
    def __getitem__(self, idx) -> Union['Sequential', T]:
        if isinstance(idx, slice):
            return self.__class__(OrderedDict(list(self._modules.items())[idx]))
        else:
            return self._get_item_by_idx(self._modules.values(), idx)

    @_copy_to_script_wrapper
    def __len__(self) -> int:
        return len(self._modules)

    @_copy_to_script_wrapper
    def __dir__(self):
        keys = super(Sequential, self).__dir__()
        keys = [key for key in keys if not key.isdigit()]
        return keys

    @_copy_to_script_wrapper
    def __iter__(self) -> Iterator[Module]:
        return iter(self._modules.values())

    def forward(self, input):
        for module in self:
            input = module(input)
        return input
```

```python
# Example of using Sequential
model = nn.Sequential(
          nn.Conv2d(1,20,5),
          nn.ReLU(),
          nn.Conv2d(20,64,5),
          nn.ReLU()
        )

# Example of using Sequential with OrderedDict
model = nn.Sequential(OrderedDict([
          ('conv1', nn.Conv2d(1,20,5)),
          ('relu1', nn.ReLU()),
          ('conv2', nn.Conv2d(20,64,5)),
          ('relu2', nn.ReLU())
        ]))
```

见`__init__`，第一个Example，add_module时，module的名称使用str(idx)，第二Example，使用dict->key。

同时，nn.Conv2d, nn.ReLU等也是一个Module。

```python
class _ConvNd(Module):
class Conv2d(_ConvNd):
```

对象创建时，将所有的算子通过add\_module()加入到容器的属性`_modules`中。`_modules`属于父类，即Module类的属性，。

## ModuleList的构建

ModuleList实际上也是一个Module对象，只是它实现了list的操作接口，表现为一个List。

```python
class ModuleList(Module):
    def __init__(self, modules: Optional[Iterable[Module]] = None) -> None:
        super(ModuleList, self).__init__()
        if modules is not None:
            self += modules

    def __iadd__(self, modules: Iterable[Module]) -> 'ModuleList':
        return self.extend(modules)

    def extend(self, modules: Iterable[Module]) -> 'ModuleList':
        offset = len(self)
        for i, module in enumerate(modules):
            self.add_module(str(offset + i), module)
        return self

    def forward(self):
        raise NotImplementedError()
```

```python
Example::

    class MyModule(nn.Module):
        def __init__(self):
            super(MyModule, self).__init__()
            self.linears = nn.ModuleList([nn.Linear(10, 10) for i in range(10)])

        def forward(self, x):
            # ModuleList can act as an iterable, or be indexed using ints
            for i, l in enumerate(self.linears):
                x = self.linears[i // 2](x) + l(x)
            return x
```
ModuleList本身不支持forward操作。  
为了方便，Example中使用一个Module来保存ModuleList，提供forward接口，在forward中遍历ModuleList。

# load_state_dict

Copies parameters and buffers from state_dict into this module and its descendants. 

`local_name_params = itertools.chain(self._parameters.items(), self._buffers.items())`

列出Module的\_parameter 和 \_buffers， 将state\_dict copy过来，通过key进行匹配。

如果strict=true，返回值中，missing\_keys表示本Module没有state\_dict中的key（miss），unexpected\_keys表示state\_dict的key不包含在Module中（多余的）。  
missing\_keys和unexpected\_keys都是站在static\_dict的角度而言的。

# 遍历Module

包括，遍历module，parameter，children，buffer。

module：当前module和子module（\_modules） 
parameter：参数，当前module和\_modules中的parameter  
children：仅仅是遍历\_modules  
buffer: 当前module和子module中的buffer  

# 总结

Module相关接口并不难理解，看代码比看doc更好。

# 参考

Pytorch Source