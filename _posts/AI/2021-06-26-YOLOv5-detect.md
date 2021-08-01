---
layout: post
title: YOLOv5模型推理与输出层
categories: "AI"
tags: AI YOLOv5
author: Jasper
---

* content
{:toc}

YOLOv5的推理与输出层，涵盖模型信息、grid、loss、设备端移植等，尤其是build_targets函数进行了超详细的注释。



# 模型加载与信息获取

`model = attempt_load(weights, map_location=device)  # load FP32 model`

本文只考虑一个模型的情况，如果考虑多个模型，参考“Pytorch 集成学习”相关内容。

YOLOv5在训练时，除了保存整个网络结构和权重，还将一些必要的信息保存在模型文件中。

```python
ckpt = {'epoch': epoch,
            'best_fitness': best_fitness,
            'training_results': results_file.read_text(),
            'model': deepcopy(de_parallel(model)).half(),
            'ema': deepcopy(ema.ema).half(),
            'updates': ema.updates,
            'optimizer': optimizer.state_dict(),
            'wandb_id': wandb_logger.wandb_run.id if loggers['wandb'] else None}

    # Save last, best and delete
    torch.save(ckpt, last)
    if best_fitness == fi:
        torch.save(ckpt, best)
```

从`'model': deepcopy(de_parallel(model)).half(),`可知，模型保存是半精度；并且保存整个模型，而不是state_dict。

当完成训练后，做了一下strip，扔掉一些不需要的信息：

```python
# Strip optimizers
for f in last, best:
    if f.exists():
        strip_optimizer(f)  # strip optimizers
```

```python
def strip_optimizer(f='best.pt', s=''):  # from utils.general import *; strip_optimizer()
    # Strip optimizer from 'f' to finalize training, optionally save as 's'
    x = torch.load(f, map_location=torch.device('cpu'))
    if x.get('ema'):
        x['model'] = x['ema']  # replace model with ema
    for k in 'optimizer', 'training_results', 'wandb_id', 'ema', 'updates':  # keys
        x[k] = None
    x['epoch'] = -1
    x['model'].half()  # to FP16
    for p in x['model'].parameters():
        p.requires_grad = False
    torch.save(x, s or f)
    mb = os.path.getsize(s or f) / 1E6  # filesize
    print(f"Optimizer stripped from {f},{(' saved as %s,' % s) if s else ''} {mb:.1f}MB")
```

如果是使用了EMA，则提取EMA作为最终的model，并将一些属性设置为None，epoch计数改成-1，转换为FP16（其实这个重复了）。

假设已经启用了EMA，某些信息被保存：  
`ema.update_attr(model, include=['yaml', 'nc', 'hyp', 'gr', 'names', 'stride', 'class_weights'])`

yaml：配置文件  
nc：类别个数  
hyp：超参  
gr：iou loss ratio，默认是1.0  
names：labels  
stride：跨度信息，表示输出层的缩放比例，默认是 [ 8., 16., 32.]  
class_weights：类别间的权重信息  

以上信息都可以在train.py或者yolo.py中看到相关的保存代码。

```python
    model.nc = nc  # attach number of classes to model
    model.hyp = hyp  # attach hyperparameters to model
    model.gr = 1.0  # iou loss ratio (obj_loss = 1.0 or iou)
    model.class_weights = labels_to_class_weights(dataset.labels, nc).to(device) * nc  # attach class weights
    model.names = names
    if isinstance(m, Detect):
        m.inplace = self.inplace
        m.stride = torch.tensor([s / x.shape[-2] for x in self.forward(torch.zeros(1, ch, s, s))])  # forward
        m.anchors /= m.stride.view(-1, 1, 1)
        check_anchor_order(m)
        self.stride = m.stride
```

保存信息在model文件中，给训练和推理带来的极大的便利，至少我们不用向往常那样，拖家带口似的：模型权重文件、label文件、yaml文件、anchors文件。注意，有的信息是在Detect层。

打印Detect层所附带的anchors：  
```python
for name, layer in model.named_modules():
    if hasattr(layer, "anchors"):
        print("==========", layer, layer.anchors)
```

```python
========== Detect(
  (m): ModuleList(
    (0): Conv2d(128, 255, kernel_size=(1, 1), stride=(1, 1))
    (1): Conv2d(256, 255, kernel_size=(1, 1), stride=(1, 1))
    (2): Conv2d(512, 255, kernel_size=(1, 1), stride=(1, 1))
  )
) tensor([[[ 1.25000,  1.62500],
         [ 2.00000,  3.75000],
         [ 4.12500,  2.87500]],

        [[ 1.87500,  3.81250],
         [ 3.87500,  2.81250],
         [ 3.68750,  7.43750]],

        [[ 3.62500,  2.81250],
         [ 4.87500,  6.18750],
         [11.65625, 10.18750]]], device='cuda:0')
```

# Detect层

Detect层是YOLOv5最后一层，包含三个输出，分别是下降stride（见stribe属性，8，16，32）倍的网格。

> 插曲：
> 当在pytorch环境中load model文件时，使用的pickle lib进行反序列化为对象，再调用对象中的方法完成推理。这时，依赖于项目中的python代码，我们可以在代码（如Detect->forward）中修改逻辑，进行调试或者变更推理过程；
> 当转换为onnx或者torchscript时，则可以使用c++进行加载和推理，此时，依赖的是纯c++环境。

```python
class Detect(nn.Module):
    def forward(self, x):
        for i in range(self.nl):
            x[i] = self.m[i](x[i])  # conv
            bs, _, ny, nx = x[i].shape  # x(bs,255,20,20) to x(bs,3,20,20,85)
            x[i] = x[i].view(bs, self.na, self.no, ny, nx).permute(0, 1, 3, 4, 2).contiguous()
            if not self.training:  # inference
                if self.grid[i].shape[2:4] != x[i].shape[2:4] or self.onnx_dynamic:
                    self.grid[i] = self._make_grid(nx, ny).to(x[i].device)

                y = x[i].sigmoid()
                if self.inplace:
                    y[..., 0:2] = (y[..., 0:2] * 2. - 0.5 + self.grid[i]) * self.stride[i]  # xy
                    y[..., 2:4] = (y[..., 2:4] * 2) ** 2 * self.anchor_grid[i]  # wh
                else:  # for YOLOv5 on AWS Inferentia https://github.com/ultralytics/yolov5/pull/2953
                    xy = (y[..., 0:2] * 2. - 0.5 + self.grid[i]) * self.stride[i]  # xy
                    wh = (y[..., 2:4] * 2) ** 2 * self.anchor_grid[i].view(1, self.na, 1, 1, 2)  # wh
                    y = torch.cat((xy, wh, y[..., 4:]), -1)
                z.append(y.view(bs, -1, self.no))

        return x if self.training else (torch.cat(z, 1), x)
```

## Forward

> 以coco 80类，输入尺寸640x640为例；但输入是可以任意设置的，比如384x640.在函数  
> def letterbox(img, new_shape=(640, 640), color=(114, 114, 114), auto=True, scaleFill=False, scaleup=True, stride=32)  
> 中，预处理resize使用的padding等比例方式，长短边都是32的倍数，长边是640。

结合[https://nextstart.online/2021/06/19/YOLOv5/](https://nextstart.online/2021/06/19/YOLOv5/)，Focus负责下降2倍，backbone中的每一个CBL负责将输入下降2倍。

Detect层将下降8，16，32倍的节点concat到一起作为输入，见网络配置文件yolov5s.yaml:  

```yaml
[[17, 20, 23], 1, Detect, [nc, anchors]],  # Detect(P3, P4, P5)
```

`[17, 20, 23]`表示layer id，构建Detect的参数`[nc, anchors]`在推理时，已经是反序列化对象中的属性，所以，这个配置在这没有参考价值。

Detect layer 的forward函数，接收的x是长度为3的一个 list of feature map。

`x[self.nl]`分别经过一个卷积，使得其大小正好是网格的各维度的乘积，.view().permute()操作之后正好是`x(bs,3,20,20,85)`。

> 插曲：
> 根据经验，当移植到端设备（比如海思平台）时，可以从这里截断，或者前一点，从卷积之后截断；从不同的位置截断作为网络的输出，推理的后处理步骤就应相应地变化。
> 甚至如果可以，不用截断，所有Detect层的操作在网络中执行，但要注意某些接口是否支持。

再看看forward的剩余部分。

grid是每一个网格三个anchor，`self.grid = [torch.zeros(1)] * self.nl  # init grid`，等于`[tensor([0.]), tensor([0.]), tensor([0.])]`。

`self.grid[i] = self._make_grid(nx, ny).to(x[i].device)`

nx和ny表示下降stride倍后的feature map尺寸，这里是网格的尺寸，对于640的输入，正好是20.

```python
def _make_grid(nx=20, ny=20):
    yv, xv = torch.meshgrid([torch.arange(ny), torch.arange(nx)])
    return torch.stack((xv, yv), 2).view((1, 1, ny, nx, 2)).float()
```

yv和xv等于两个20x20的二维tensor。然后使用torch.stack对它们沿着第2维（dim可选0，1，2）进行堆叠，得到一个三维张量。然后将其view为一张每个点包含两个坐标的网格。

> torch.stack表示张量堆叠，第一个参数：张量队列，维度相同，第二参数：堆叠沿着哪个维度进行。重要是理解第二个参数，比如2维。dim=0，表示直接将两个张量毫无修改的叠在一起，得到一个三维张量；dim=1，表示从张量队列的每一个张量中取出第一行，堆叠在一起得到新张量的一个维度数据。
> 自己整一个2x2的试一把，啥都清楚了。

```python
y = x[i].sigmoid()
y[..., 0:2] = (y[..., 0:2] * 2. - 0.5 + self.grid[i]) * self.stride[i]  # xy
y[..., 2:4] = (y[..., 2:4] * 2) ** 2 * self.anchor_grid[i]  # wh
```

要知道上面的语句干什么事，首先要弄清楚这里输出的box信息是怎么表示的，这个要从dataset的加载和loss的计算（边框回归）中找答案。

先看dataset对label文件中的box的处理：  
在label文件中，box是以中心点+长宽的方式存放的，也就是xywhn的方式；经过增加处理后，box变成了xyxy的绝对表示，下面的代码，就将xyxy还原到xywhn。
`labels[:, 1:5] = xyxy2xywhn(labels[:, 1:5], w=img.shape[1], h=img.shape[0])  # xyxy to xywh normalized`  

# loss计算

```python
class ComputeLoss:
    def __call__(self, p, targets):  # predictions, targets, model
        tcls, tbox, indices, anchors = self.build_targets(p, targets)  # targets
        # Losses
        for i, pi in enumerate(p):  # layer index, layer predictions
            # 这些indices是根据标注框，根据build_targets函数生成的
            b, a, gj, gi = indices[i]  # image, anchor, gridy, gridx
            tobj = torch.zeros_like(pi[..., 0], device=device)  # target obj

            n = b.shape[0]  # number of targets
            if n:
                # 通过索引，提取预测结果中的某些预测结果来进行loss的计算
                ps = pi[b, a, gj, gi]  # prediction subset corresponding to targets

                # 后面的是分别计算边框回归损失、目标置信度损失、类别损失

                # Regression
                pxy = ps[:, :2].sigmoid() * 2. - 0.5 # 区间[-0.5, 1.5]
                pwh = (ps[:, 2:4].sigmoid() * 2) ** 2 * anchors[i]
                pbox = torch.cat((pxy, pwh), 1)  # predicted box
                iou = bbox_iou(pbox.T, tbox[i], x1y1x2y2=False, CIoU=True)  # iou(prediction, target)
                lbox += (1.0 - iou).mean()  # iou loss

                # Objectness
                tobj[b, a, gj, gi] = (1.0 - self.gr) + self.gr * iou.detach().clamp(0).type(tobj.dtype)  # iou ratio

                # Classification
                if self.nc > 1:  # cls loss (only if multiple classes)
                    t = torch.full_like(ps[:, 5:], self.cn, device=device)  # targets
                    t[range(n), tcls[i]] = self.cp
                    lcls += self.BCEcls(ps[:, 5:], t)  # BCE
```

build_target会在后面的附录中给出，它的作用是生成target（标注目标）的基本信息，包括：目标类别、目标box、一些索引信息、anchors。

其中，Regression loss的计算，也正好与前一小节中，Detect layer forward函数计算xy,wh的方法相对应。

比较简单，对于loss理解可以参考：[https://www.freesion.com/article/48061348692/](https://www.freesion.com/article/48061348692/)

# 附录

## build_target注解

```python
    # build_targets总共会生成5份网格信息，经过筛选后，包括网格自身和与网格中心点最相邻的两个格子；
    # 也就是说，一个目标框会得到3个target，它们相邻（特殊情况下只有1个）.
    def build_targets(self, p, targets):
        # p: 预测结果，一个list，3个元素分别表示P3 P4 P5的预测值
        # (Pdb) p(p[0].shape)
        # torch.Size([8, 3, 80, 80, 85])
        # (Pdb) p(p[1].shape)
        # torch.Size([8, 3, 40, 40, 85])
        # (Pdb) p(p[2].shape)
        # torch.Size([8, 3, 20, 20, 85])
        # p：第0个元素shape：torch.Size([8, 3, 80, 80, 85])
        # p：8，batch-size；3，三个anchor；80,80，表示网格大小；85，表示一个格子的输出向量(class + 5 = 85)

        # targets(image,class,x,y,w,h)：图像index，标签index，标注框
        # targets：每一行表示一个标注框，及所对应的图像index，所属的标签index
        # targets：除了标注框不会重复，其它两个index是可能会重复的，因为一张图可能有多个标注框
        # 比如：下面有两张图片，index=6,7，分别有4，3个标注框
        # [6.00000e+00, 5.60000e+01, 4.84862e-01, 5.06090e-01, 8.91676e-02, 1.29275e-01],
        # [6.00000e+00, 5.60000e+01, 8.31239e-01, 5.44641e-01, 3.37522e-01, 4.32708e-01],
        # [6.00000e+00, 6.00000e+01, 7.19967e-01, 7.71785e-01, 5.60066e-01, 4.56429e-01],
        # [6.00000e+00, 4.00000e+01, 7.52664e-01, 6.22213e-01, 1.32134e-01, 3.20710e-01],
        # [7.00000e+00, 0.00000e+00, 7.16337e-01, 4.10335e-02, 4.57878e-02, 5.45111e-02],
        # [7.00000e+00, 0.00000e+00, 5.97853e-01, 3.69099e-02, 3.09791e-02, 3.78452e-02],
        # [7.00000e+00, 2.00000e+01, 5.95949e-01, 7.73930e-02, 7.91287e-02, 4.53688e-02],
        # 标签index == 5.6+01，表示56

        # Build targets for compute_loss(), input targets(image,class,x,y,w,h)
        na, nt = self.na, targets.shape[0]  # number of anchors(default == 3)， and number of targets
        tcls, tbox, indices, anch = [], [], [], []
        gain = torch.ones(7, device=targets.device)  # normalized to gridspace gain

        # 0 ~ (na-1)
        # view(na, 1)：表示拓展为二维向量，每一行一个元素
        # repeat(1, nt)：表示，第一维不变，第二维拓展为nt个元素，且所拓展元素与原值相同
        # 最后：得到一个na x nt的矩阵，表示anchor index
        ai = torch.arange(na, device=targets.device).float().view(na, 1).repeat(1, nt)  # same as .repeat_interleave(nt)

        # targets.repeat(na, 1, 1)：targets从2维拓展到3维，第二、三维不做增减，第一维直接拓展na倍
        # 相当于直接将targets复制na份，组成一个list
        # torch.cat：将3维的targets与2维的ai拼接，沿着第2维（也就是第三维），但是ai没有第三维
        # ai[:, :, None]：先将矩阵看成三维（一个元素也看成一维），直接在第三维增加一维，ai的第三维变成一个向量，而且是只有一个元素的向量
        # ai[:, :, None].shape
        # torch.Size([3, 97, 1])
        # ai[None, :, :].shape
        # torch.Size([1, 3, 97])
        # torch.cat的结果是一个3维矩阵，第三维被直接追加，变成了(image,class,x,y,w,h,anchor_index)，共7个数
        # 正好符合代码注解：append anchor indices， 追加 anchor indices(indexes)
        targets = torch.cat((targets.repeat(na, 1, 1), ai[:, :, None]), 2)  # append anchor indices

        # 偏移量是半个格子
        g = 0.5  # bias
        off = torch.tensor([[0, 0],
                            [1, 0], [0, 1], [-1, 0], [0, -1],  # j,k,l,m
                            # [1, 1], [1, -1], [-1, 1], [-1, -1],  # jk,jm,lk,lm
                            ], device=targets.device).float() * g  # offsets

        for i in range(self.nl):
            # self.anchors：来自Detect layer， 是一个二维数组，共3组anchors，分别对应三个输出layer
            # for k in 'na', 'nc', 'nl', 'anchors':
            #     setattr(self, k, getattr(det, k))
            # 在Detect layer中，anchors是除以了下降倍数，也就是网格中每个格子的跨度，可理解为anchors所占的格子数
            # m.anchors /= m.stride.view(-1, 1, 1)
            # 获取到输入本层的anchors，默认共3个
            anchors = self.anchors[i]

            # 将网格数（比如：80x80）填充到变量gain相应的位置，其它位置全是 1
            gain[2:6] = torch.tensor(p[i].shape)[[3, 2, 3, 2]]  # xyxy gain

            # Match targets to anchors
            # targets中是归一化的xy尺寸，将其乘以网格数，映射到网格上，比如0.5 x 80 = 40，落在第40个格子上
            t = targets * gain
            if nt:
                # Matches
                # anchors[:, None]：相当于anchors[:, None, :]，先看成三维，在第二维上拓展一维
                # 可见，预测值p中的w,h，表示目标的宽和长，所占的格子数
                # r 就表示 w,h ratio，可理解为，w,h 占多少个anchor
                r = t[:, :, 4:6] / anchors[:, None]  # wh ratio

                # w,h 必须满足这样的范围：1/'anchor_t' < w,h ratio < 'anchor_t'，结果是，w,h不能太小，也不能太大
                # 限定目标框不应大于anchor的4倍（默认是4，当我们的目标尺寸偏差非常大，可能要考虑修改该超参）
                j = torch.max(r, 1. / r).max(2)[0] < self.hyp['anchor_t']  # compare
                # j = wh_iou(anchors, t[:, 4:6]) > model.hyp['iou_t']  # iou(3,n)=wh_iou(anchors(3,2), gwh(n,2))
                t = t[j]  # filter

                # Offsets
                # 目标框的中心点，xyxy中的第一个xy，表示以整个大网格左上角为坐标原点的中心点坐标
                gxy = t[:, 2:4]  # grid xy
                # gxi = 用网格的尺寸 - gxy，表示以整个大网格右下角为坐标原点的中心点的坐标
                gxi = gain[[2, 3]] - gxy  # inverse
                # gxy % 1. < g：提取小数部分，将 < g的部分记下True，否则记下False
                # 取了小数后，筛选条件就相对于中心点本身所在的小网格而言了
                # 我姑且称下面这两个条件为“中心点条件”
                j, k = ((gxy % 1. < g) & (gxy > 1.)).T
                l, m = ((gxi % 1. < g) & (gxi > 1.)).T
                # 将一个全1的向量，与j,k,l,m四个向量进行stack操作，得到一个二维的张量（5,）
                j = torch.stack((torch.ones_like(j), j, k, l, m))
                # 对targets进行筛选：先将t拓展5倍，根据j的内容可知，第一维全选，后面几维根据jklm进行筛选
                # 由于j是一个二维张量，t 最终从一个三维张量变成二维张量（少了一维）
                # ipdb> p j.shape
                # torch.Size([5, 276])
                # ipdb> t.shape
                # torch.Size([276, 7])
                # ipdb> t.repeat((5, 1, 1)).shape
                # torch.Size([5, 276, 7])
                # 小结一下：t被重复五份，分别对满足给定的“中心点条件”的目标都选下来
                t = t.repeat((5, 1, 1))[j]
                # ipdb> torch.zeros_like(gxy).shape
                # torch.Size([276, 2])
                # ipdb> torch.zeros_like(gxy)[None].shape
                # torch.Size([1, 276, 2])
                # ipdb> off[:, None].shape
                # torch.Size([5, 1, 2])
                # ipdb> (torch.zeros_like(gxy)[None] + off[:, None]).shape
                # torch.Size([5, 276, 2])
                # + 操作：两个张量维度不相同，且其中有一个维度是1，则将1广播到对应更大的维度，再相加
                # 比如，完整的 + 操作可以替换为： torch.zeros_like(gxy).repeat(5,1,1) + off[:, None]
                # 本条语句最终得到：一个形如 t 的偏置，offsets.shape = t.shape
                # 注意这里的t是进行了5倍扩展，并由j筛选过，所以，偏置也应当执行同样的扩展和筛选
                # 至此，我们得到了上下左右加中心点，共5个点的偏移量（实际是3个）
                offsets = (torch.zeros_like(gxy)[None] + off[:, None])[j]

                # 对于t和offsets，可以这么理解：t表示5个一样的中心点，5份；offsets表示这5份中心点的偏移量；
                # t - offsets 立马得到5个位置不一样的中心点
                # 但是，t经过了“中心点条件”筛选，只取了偏移小于g==0.5的两个中心点，所以，5个点中的另外两个被抛弃了。

                # 值得注意的是，假设中心点正好是(0.5,0.5)，那么最终只有中心点本身被留下，其它都被过滤掉了，相当于没有做拓展
            else:
                t = targets[0]
                offsets = 0

            # Define
            b, c = t[:, :2].long().T  # image, class
            gxy = t[:, 2:4]  # grid xy
            gwh = t[:, 4:6]  # grid wh
            # gxy - offsets：得到3个中心点坐标
            # .long()：取整，具体到那个网格，不用小数了
            # 后面的clamp_的作用是避免超出范围，比较，网格边沿的点，它们的相邻点可能超出网格的外面
            gij = (gxy - offsets).long()
            gi, gj = gij.T  # grid xy indices

            # Append
            a = t[:, 6].long()  # anchor indices
            indices.append((b, a, gj.clamp_(0, gain[3] - 1), gi.clamp_(0, gain[2] - 1)))  # image, anchor, grid indices
            tbox.append(torch.cat((gxy - gij, gwh), 1))  # box，中心点偏移(offsets)和宽高
            anch.append(anchors[a])  # anchors
            tcls.append(c)  # class

        return tcls, tbox, indices, anch
```

3个相邻点的图示：

![](https://www.freesion.com/images/444/75b593c73852ed76a1013bf5ef28b5c4.png)

## loss公式

![](https://www.freesion.com/images/69/17dfa84fe3750ab63c7ec50856046d7d.png)

![](https://www.freesion.com/images/54/4c332b4656f3ac2fb81f718225aebb46.png)