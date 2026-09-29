---@meta EggyAPI

---@alias Any any
---@alias Bool boolean
---@alias Float number
---@alias Int number
---@alias Long number
---@alias String string
---@alias Table table

--========================== 数据 Data ==========================

---Animation 动画资源引用对象
---**适用范围**: 客户端和服务端
---@class Animation
---@field AnimationId String 动画资源标识，asset URI 格式
---@field Name String 动画显示名称（解析后的短名）
Animation = {}

---创建一个新的 Animation
---**适用范围**: 客户端和服务端
---@param Name String 动画显示名称
---@param AnimationId String 动画资源标识，asset URI 格式
---@return Animation
function Animation.New(Name, AnimationId) end

---轴集合
---@class Axes
---@field Back Bool 后面（Z 轴派生）
---@field Bottom Bool 底面（Y 轴派生）
---@field Front Bool 前面（Z 轴派生）
---@field Left Bool 左面（X 轴派生）
---@field Right Bool 右面（X 轴派生）
---@field Top Bool 顶面（Y 轴派生）
---@field x Bool X 轴
---@field y Bool Y 轴
---@field z Bool Z 轴
Axes = {}

---可选名称：X | Y | Z
---**适用范围**: 客户端和服务端
---@param ... String 轴名称（可变参数）
---@return Axes
function Axes.New(...) end

---位掩码
---@class BitMask
local BitMask = {}

---获取指定位是否被设置
---@param bitIndex Int 位序号（1-64）
---@return Bool 该位是否被设置
function BitMask:GetBit(bitIndex) end

---轴对齐包围盒
---@class BoundingBox
---@field Max Vector3 最大值
---@field Min Vector3 最小值
BoundingBox = {}

---获取中心点
---@return Vector3
function BoundingBox:GetCenter() end

---获取包围盒尺寸
---@return Vector3
function BoundingBox:GetExtent() end

---获取最大值
---@return Vector3
function BoundingBox:GetMax() end

---获取最小值
---@return Vector3
function BoundingBox:GetMin() end

---创建轴对齐包围盒
---**适用范围**: 客户端和服务端
---@param min Vector3 最小值
---@param max Vector3 最大值
---@return BoundingBox
function BoundingBox.New(min, max) end

---设置最大值
---@param v Vector3
function BoundingBox:SetMax(v) end

---设置最小值
---@param v Vector3
function BoundingBox:SetMin(v) end

---CFrame 是表示 3D 空间中位置和旋转的坐标帧，用于描述物体的世界变换或局部坐标系。
---@class CFrame
---@field LeftVector Vector3 左方向单位向量（-RightVector）
---@field LookVector Vector3 前方朝向单位向量（-Z 方向）
---@field Position Vector3 CFrame 的平移分量，表示坐标帧原点在世界空间中的位置
---@field RightVector Vector3 右向量
---@field Rotation CFrame 提取当前 CFrame 的旋转部分，位置归零后得到的纯旋转 CFrame
---@field UpVector Vector3 上方向单位向量（旋转矩阵 column 1）
---@field X Float CFrame 平移分量在世界坐标系下的 X 轴值
---@field XVector Vector3 旋转矩阵 column 0（同 RightVector）
---@field Y Float CFrame 平移分量在世界坐标系下的 Y 轴值
---@field YVector Vector3 旋转矩阵 column 1（同 UpVector）
---@field Z Float CFrame 平移分量在世界坐标系下的 Z 轴值
---@field ZVector Vector3 旋转矩阵 column 2（LookVector）
CFrame = {}

---计算当前 CFrame 与目标 CFrame 旋转部分之间的最小夹角，结果单位为弧度
---@param other CFrame 用于比较的另一个 CFrame
---@return Float
function CFrame:AngleBetween(other) end

---从旋转轴和绕该轴的旋转角构造仅含旋转的 CFrame，位置为原点
---@param axis Vector3 旋转轴的单位向量
---@param angle Float 绕轴旋转的角度，单位为弧度
---@return CFrame
function CFrame.FromAxisAngle(axis, angle) end

---按指定旋转顺序从欧拉角构造仅含旋转的 CFrame，位置为原点
---@param rx Float 绕 X 轴旋转的角度，单位为弧度
---@param ry Float 绕 Y 轴旋转的角度，单位为弧度
---@param rz Float 绕 Z 轴旋转的角度，单位为弧度
---@param order Int 旋转顺序，对应 Enum.RotationOrder（XYZ=0, XZY=1, YZX=2, YXZ=3, ZXY=4, ZYX=5）
---@return CFrame
function CFrame.FromEulerAngles(rx, ry, rz, order) end

---按 XYZ 顺序从外部欧拉角构造仅含旋转的 CFrame，位置为原点
---@param rx Float 绕 X 轴旋转的角度，单位为弧度
---@param ry Float 绕 Y 轴旋转的角度，单位为弧度
---@param rz Float 绕 Z 轴旋转的角度，单位为弧度
---@return CFrame
function CFrame.FromEulerAnglesXYZ(rx, ry, rz) end

---按 YXZ 顺序从外部欧拉角构造仅含旋转的 CFrame，位置为原点
---@param rx Float 绕 X 轴旋转的角度，单位为弧度
---@param ry Float 绕 Y 轴旋转的角度，单位为弧度
---@param rz Float 绕 Z 轴旋转的角度，单位为弧度
---@return CFrame
function CFrame.FromEulerAnglesYXZ(rx, ry, rz) end

---由位置和旋转矩阵的列向量构造 CFrame，可显式提供三列向量或仅提供两列由叉乘自动推导第三列
---@overload fun(pos: Vector3, vX: Vector3, vY: Vector3, vZ: Vector3): CFrame —— 位置+三列向量
---@overload fun(pos: Vector3, vX: Vector3, vY: Vector3): CFrame —— 位置+两列向量（vZ 由 vX:Cross(vY) 推导）
function CFrame.FromMatrix(...) end

---按 YXZ 顺序从朝向角度构造仅含旋转的 CFrame，是 FromEulerAnglesYXZ 的别名
---@param rx Float 绕 X 轴旋转的角度，单位为弧度
---@param ry Float 绕 Y 轴旋转的角度，单位为弧度
---@param rz Float 绕 Z 轴旋转的角度，单位为弧度
---@return CFrame
function CFrame.FromOrientation(rx, ry, rz) end

---构造将向量 from 旋转到向量 to 的最短旋转 CFrame，位置为原点
---@param from Vector3 起始方向向量
---@param to Vector3 目标方向向量
---@return CFrame
function CFrame.FromRotationBetweenVectors(from, to) end

---在指定误差范围内比较两个 CFrame 是否近似相等，适用于浮点容差判断
---@param other CFrame 用于比较的另一个 CFrame
---@param epsilon Float 允许的最大分量误差，默认 1e-5
---@return Bool
function CFrame:FuzzyEq(other, epsilon) end

---返回 CFrame 的全部 12 个数值分量：位置 x/y/z 以及 3×3 旋转矩阵（行优先 R00..R22）
---@return Float 位置 X
---@return Float 位置 Y
---@return Float 位置 Z
---@return Float 旋转矩阵 [0][0]
---@return Float 旋转矩阵 [0][1]
---@return Float 旋转矩阵 [0][2]
---@return Float 旋转矩阵 [1][0]
---@return Float 旋转矩阵 [1][1]
---@return Float 旋转矩阵 [1][2]
---@return Float 旋转矩阵 [2][0]
---@return Float 旋转矩阵 [2][1]
---@return Float 旋转矩阵 [2][2]
function CFrame:GetComponents() end

---返回单位 CFrame，位置位于原点且旋转为零，等价于 CFrame.New()
---@return CFrame
function CFrame.Identity() end

---返回当前 CFrame 的逆变换，使得 self * self:Inverse() 等于单位 CFrame
---@return CFrame
function CFrame:Inverse() end

---在当前 CFrame 与目标 CFrame 之间插值
---@param goal CFrame 插值目标 CFrame
---@param alpha Float 插值系数
---@return CFrame
function CFrame:Lerp(goal, alpha) end

---构造一个位于 at 点、LookVector 沿 dir 方向的 CFrame，是 LookAt 的方向版本
---@param at Vector3 新 CFrame 的位置
---@param dir Vector3 希望沿其方向的世界空间向量
---@param up Vector3 参考上方向，用于消除滚转自由度，默认 (0,1,0)
---@return CFrame
function CFrame.LookAlong(at, dir, up) end

---保持自身位置不变，调整旋转使坐标帧的 LookVector 指向目标点
---@param target Vector3 希望朝向的世界坐标点
---@param up Vector3 参考上方向，用于消除滚转自由度，默认 (0,1,0)
---@return CFrame
function CFrame:LookAt(target, up) end

---构造一个位于 at 点、LookVector 指向 target 点的 CFrame
---@param at Vector3 新 CFrame 的位置
---@param target Vector3 希望朝向的目标点
---@param up Vector3 参考上方向，用于消除滚转自由度，默认 (0,1,0)
---@return CFrame
function CFrame.LookAt(at, target, up) end

---构造 CFrame，根据参数数量与类型自动选择重载（无参单位、仅位置、位置+朝向、位置+四元数、位置+旋转矩阵）
---@overload fun(): CFrame —— Identity CFrame
---@overload fun(pos: Vector3): CFrame —— 仅位置
---@overload fun(pos: Vector3, lookAt: Vector3): CFrame —— 位置+朝向
---@overload fun(x: Float, y: Float, z: Float): CFrame —— 仅位置（xyz）
---@overload fun(x: Float, y: Float, z: Float, qX: Float, qY: Float, qZ: Float, qW: Float): CFrame —— 位置+四元数
---@overload fun(x: Float, y: Float, z: Float, R00: Float, R01: Float, R02: Float, R10: Float, R11: Float, R12: Float, R20: Float, R21: Float, R22: Float): CFrame —— 位置+旋转矩阵（行优先）
function CFrame.New(...) end

---对旋转矩阵执行 Gram-Schmidt 正交化，修正长时间累乘导致的数值漂移，返回正交化后的新 CFrame
---@return CFrame
function CFrame:Orthonormalize() end

---将世界坐标系下的点变换到当前 CFrame 所定义的局部坐标系，同时考虑旋转和平移
---@param point Vector3 世界坐标系下的点坐标
---@return Vector3
function CFrame:PointToObjectSpace(point) end

---将局部坐标系下的点变换到世界坐标系，同时考虑旋转和平移
---@param point Vector3 局部坐标系下的点坐标
---@return Vector3
function CFrame:PointToWorldSpace(point) end

---将旋转部分分解为单一旋转轴及绕该轴的旋转角度（轴角表示）
---@return Vector3 旋转轴
---@return Float 旋转角度（弧度）
function CFrame:ToAxisAngle() end

---按指定旋转顺序将旋转部分分解为欧拉角，分别返回绕 X/Y/Z 轴的旋转弧度
---@param order Int 旋转顺序，对应 Enum.RotationOrder（XYZ=0, XZY=1, YZX=2, YXZ=3, ZXY=4, ZYX=5），默认 XYZ
---@return Float X轴旋转（弧度）
---@return Float Y轴旋转（弧度）
---@return Float Z轴旋转（弧度）
function CFrame:ToEulerAngles(order) end

---按 XYZ 顺序将旋转部分分解为外部欧拉角，分别返回绕 X/Y/Z 轴的旋转弧度
---@return Float X轴旋转（弧度）
---@return Float Y轴旋转（弧度）
---@return Float Z轴旋转（弧度）
function CFrame:ToEulerAnglesXYZ() end

---按 YXZ 顺序将旋转部分分解为外部欧拉角，分别返回绕 X/Y/Z 轴的旋转弧度
---@return Float X轴旋转（弧度）
---@return Float Y轴旋转（弧度）
---@return Float Z轴旋转（弧度）
function CFrame:ToEulerAnglesYXZ() end

---将传入的世界坐标 CFrame 变换回当前 CFrame 所定义的局部坐标系，等价于 self:Inverse() * cf
---@param cf CFrame 世界坐标系下的 CFrame
---@return CFrame
function CFrame:ToObjectSpace(cf) end

---按 YXZ 顺序将旋转部分分解为朝向角度，等价于 ToEulerAnglesYXZ，返回值单位为弧度
---@return Float X轴旋转（弧度）
---@return Float Y轴旋转（弧度）
---@return Float Z轴旋转（弧度）
function CFrame:ToOrientation() end

---将传入的局部坐标 CFrame 变换到世界坐标系，等价于 self * cf
---@param cf CFrame 局部坐标系下的 CFrame
---@return CFrame
function CFrame:ToWorldSpace(cf) end

---将世界坐标系下的方向向量旋转到当前 CFrame 的局部坐标系，仅应用旋转、忽略平移
---@param vector Vector3 世界坐标系下的方向向量
---@return Vector3
function CFrame:VectorToObjectSpace(vector) end

---将局部坐标系下的方向向量旋转到世界坐标系，仅应用旋转、忽略平移
---@param vector Vector3 局部坐标系下的方向向量
---@return Vector3
function CFrame:VectorToWorldSpace(vector) end

---阵营数据
---**适用范围**: 客户端和服务端
---@class Camp
---@field PlayerAdded Signal<fun(player: Player)> 当有玩家加入阵营时触发。回调参数：player 玩家
---@field PlayerRemoved Signal<fun(player: Player)> 当有玩家离开阵营时触发。回调参数：player 玩家
local Camp = {}

---获取阵营玩家列表（迭代器）
---**适用范围**: 客户端和服务端
---@return function 阵营玩家列表
function Camp:GetPlayers() end

---刚体本地碰撞回调信息
---**适用范围**: 客户端和服务端
---@class CollisionCallbackInfo
---@field OtherUnit Unit 与本单位开始或结束碰撞的另一个单位
local CollisionCallbackInfo = {}

---RGBA 颜色
---@class Color
---@field a Float 不透明度
---@field b Float 蓝色分量
---@field g Float 绿色分量
---@field r Float 红色分量
Color = {}

---线性插值两个颜色
---**适用范围**: 客户端和服务端
---@param lhs Color
---@param rhs Color
---@param u Float 插值因子 [0, 1]
---@return Color
function Color.Intrp(lhs, rhs, u) end

---逐分量取最大值
---**适用范围**: 客户端和服务端
---@param lhs Color
---@param rhs Color
---@return Color
function Color.Max(lhs, rhs) end

---逐分量取最小值
---**适用范围**: 客户端和服务端
---@param lhs Color
---@param rhs Color
---@return Color
function Color.Min(lhs, rhs) end

---创建一个新的 Color
---**适用范围**: 客户端和服务端
---@param r Float
---@param g Float
---@param b Float
---@param a Float
---@return Color
function Color.New(r, g, b, a) end

---逐分量阶跃比较
---**适用范围**: 客户端和服务端
---@param lhs Color
---@param rhs Color
---@return Color
function Color.Step(lhs, rhs) end

---Color3 颜色类型
---@class Color3
---@field b Float 蓝色分量
---@field g Float 绿色分量
---@field r Float 红色分量
Color3 = {}

---从 HSV 创建
---**适用范围**: 客户端和服务端
---@param h Float 色相 [0, 1]
---@param s Float 饱和度 [0, 1]
---@param v Float 明度 [0, 1]
---@return Color3
function Color3.FromHSV(h, s, v) end

---从 16 进制颜色串创建（接受 #RRGGBB / RRGGBB / RGB 三种形式）
---**适用范围**: 客户端和服务端
---@param hex String
---@return Color3
function Color3.FromHex(hex) end

---从 0-255 整数创建
---**适用范围**: 客户端和服务端
---@param r Int
---@param g Int
---@param b Int
---@return Color3
function Color3.FromRGB(r, g, b) end

---线性插值
---@param other Color3
---@param alpha Float
---@return Color3
function Color3:Lerp(other, alpha) end

---创建 Color3
---**适用范围**: 客户端和服务端
---@param r Float
---@param g Float
---@param b Float
---@return Color3
function Color3.New(r, g, b) end

---转换为 HSV，返回色相、饱和度、明度（h, s, v）
---@return Float 色相 [0， 1]
---@return Float 饱和度 [0， 1]
---@return Float 明度 [0， 1]
function Color3:ToHSV() end

---转换为 6 位大写 16 进制颜色串（不含 # 前缀）
---@return String
function Color3:ToHex() end

---颜色序列
---@class ColorSequence
---@field Keypoints ColorSequenceKeypoint[] 关键帧列表
ColorSequence = {}

---创建颜色序列
---**适用范围**: 客户端和服务端
---@param color Any 颜色或关键帧数组
---@return ColorSequence
function ColorSequence.New(color) end

---颜色序列关键帧
---@class ColorSequenceKeypoint
---@field Time Float 时间
---@field Value Color3 颜色值
ColorSequenceKeypoint = {}

---创建关键帧
---**适用范围**: 客户端和服务端
---@param time Float
---@param color Color3
---@return ColorSequenceKeypoint
function ColorSequenceKeypoint.New(time, color) end

---道具信息
---@class CommodityInfo
---@field CommodityId Int 道具ID
---@field CommodityNum Int 道具数量
local CommodityInfo = {}

---事件信号的连接句柄，代表一次有效的事件订阅，用于在不再需要时取消监听。
---**适用范围**: 客户端和服务端
---@class Connection
local Connection = {}

---断开连接，不再接收后续事件
---**适用范围**: 客户端和服务端
function Connection:Disconnect() end

---自定义外观数据，由用户通过「合并外观」功能或自定义外观管理面板创建的可复用外观预设；由一个主模型和若干个子模型（SubCustomAppearance）组成，记录模型资源、皮肤、染色区域、材质参数、透明度、阴影投射等外观属性。创建后可在资源管理器的「自定义」分类中查看与管理，并通过属性面板的外观下拉应用到组件；外观保存后，已使用它的组件会自动更新为新外观。
---@class CustomAppearance
---@field CastShadow Bool 主模型是否投射阴影。
---@field Id String 自定义外观ID，由系统生成，只读。
---@field MainModelVisible Bool 是否显示主模型；关闭后仅显示子模型。
---@field MaterialParam MaterialParam 主模型的材质参数，用于调整模型的材质表现。
---@field MaterialParamList MaterialParam[] 与 SkinSlots 按索引平行对应的逐槽位材质参数；槽位元素为空时回落该槽位皮肤自带的材质参数。
---@field ModelAlpha Float 主模型的透明度，取值 0（完全透明）~ 1（不透明）。
---@field ModelColor1 Color 主模型染色区域 1 的颜色；仅当模型支持该染色区域时生效。
---@field ModelColor2 Color 主模型染色区域 2 的颜色；仅当模型支持该染色区域时生效。
---@field ModelColor3 Color 主模型染色区域 3 的颜色；仅当模型支持该染色区域时生效。
---@field ModelColor4 Color 主模型染色区域 4 的颜色；仅当模型支持该染色区域时生效。
---@field Name String 外观的名称。
---@field RenderMeshId String 主模型使用的模型资源（Mesh）。
---@field Rotation Quaternion 外观整体的旋转（四元数）。
---@field Scale Vector3 外观整体的缩放。
---@field SkinId String 主模型应用的皮肤；为空时不设置皮肤。
---@field SubAppearance SubCustomAppearance[] 子模型列表；每个元素为一个 SubCustomAppearance（子自定义外观）。
local CustomAppearance = {}

---数据存储集合，提供键值对的增删改查操作。
---不可通过构造函数或元表实例化，仅由 DataStoreService:GetDataStore() / GetGlobalDataStore() / GetOrderedDataStore() 返回。
---**适用范围**: 仅服务端
---@class DataStore
local DataStore = {}

---获取指定 key 的数据
---**适用范围**: 仅服务端
---@param key String 键名
---@param options? DataStoreGetOptions 可选参数, 优先级高于 DataStore 初始化时的 DataStoreOptions, 可通过 DataStoreGetOptions.New() 创建
---@return Any 数据值， key 不存在时返回 nil
---@return DataStoreKeyInfo 键信息 (需 WithKeyInfo=true 才会返回)
function DataStore:GetAsync(key, options) end

---获取指定版本的数据
---**适用范围**: 仅服务端
---@param key String 键名
---@param version String 版本号
---@param options? DataStoreGetVersionOptions 可选参数, 优先级高于 DataStore 初始化时的 DataStoreOptions, 可通过 DataStoreGetVersionOptions.New() 创建
---@return Any 数据值， 版本或 key 不存在时返回 nil
---@return DataStoreKeyInfo 键信息 (需 WithKeyInfo=true 才会返回)
function DataStore:GetVersionAsync(key, version, options) end

---获取指定时间点的数据
---**适用范围**: 仅服务端
---@param key String 键名
---@param timestamp Int 时间戳 (毫秒)
---@param options? DataStoreGetVersionOptions 可选参数, 优先级高于 DataStore 初始化时的 DataStoreOptions, 可通过 DataStoreGetVersionOptions.New() 创建
---@return Any 数据值， 该时间点无对应版本时返回 nil
---@return DataStoreKeyInfo 键信息 (需 WithKeyInfo=true 才会返回)
function DataStore:GetVersionAtTimeAsync(key, timestamp, options) end

---对指定 key 的数值进行原子自增
---**适用范围**: 仅服务端
---@param key String 键名
---@param delta Int 自增值 (非零)
---@param options? DataStoreIncrementOptions 可选参数, 优先级高于 DataStore 初始化时的 DataStoreOptions, 可通过 DataStoreIncrementOptions.New() 创建
---@return Any 自增后的值
---@return DataStoreKeyInfo 键信息 (需 WithKeyInfo=true 才会返回)
function DataStore:IncrementAsync(key, delta, options) end

---分页列出 key
---**适用范围**: 仅服务端
---@param prefix? String 前缀过滤, 默认空字符串
---@param pageSize? Int 页大小, 默认 0 (使用服务端默认值)
---@param cursor? String 分页游标
---@param options? DataStoreListKeyOptions 可选参数, 优先级高于 DataStore 初始化时的 DataStoreOptions, 可通过 DataStoreListKeyOptions.New() 创建
---@return DataStoreKeyBriefInfoPages 分页迭代器
function DataStore:ListKeysAsync(prefix, pageSize, cursor, options) end

---列出指定 key 的历史版本
---**适用范围**: 仅服务端
---@param key String 键名
---@param ascending? Bool 排序方向, true 时按版本更新时间升序, false 时降序
---@param minDate? Int 最小时间 (毫秒)
---@param maxDate? Int 最大时间 (毫秒)
---@param pageSize? Int 页大小, 默认 0 (使用服务端默认值)
---@return DataStoreVersionInfoPages 分页迭代器
function DataStore:ListVersionsAsync(key, ascending, minDate, maxDate, pageSize) end

---删除指定 key
---**适用范围**: 仅服务端
---@param key String 键名
---@param options? DataStoreRemoveOptions 可选参数, 优先级高于 DataStore 初始化时的 DataStoreOptions, 可通过 DataStoreRemoveOptions.New() 创建
---@return Any 删除前的数据值， key 不存在时返回 nil
---@return DataStoreKeyInfo 键信息 (需 WithKeyInfo=true 才会返回)
function DataStore:RemoveAsync(key, options) end

---删除指定版本
---**适用范围**: 仅服务端
---@param key String 键名
---@param version String 版本号
---@param options? DataStoreRemoveVersionOptions 可选参数, 优先级高于 DataStore 初始化时的 DataStoreOptions, 可通过 DataStoreRemoveVersionOptions.New() 创建
---@return Any 删除前的数据值， 版本不存在时返回 nil
---@return DataStoreKeyInfo 键信息 (需 WithKeyInfo=true 才会返回)
function DataStore:RemoveVersionAsync(key, version, options) end

---设置指定 key 的数据
---**适用范围**: 仅服务端
---@param key String 键名
---@param value Any 数据值
---@param options? DataStoreSetOptions 可选参数, 优先级高于 DataStore 初始化时的 DataStoreOptions, 可通过 DataStoreSetOptions.New() 创建
---@return String 版本号
---@return DataStoreKeyInfo 键信息 (需 WithKeyInfo=true 才会返回)
function DataStore:SetAsync(key, value, options) end

---先读后写的复合更新操作 (Read-Modify-Write)
---**适用范围**: 仅服务端
---@param key String 键名
---@param transformFunction function 变换函数 function(currentValue, keyInfo) -> newValue, DataStoreSetOptions?; 返回 newValue=nil 时放弃更新; 可返回 DataStoreSetOptions 自定义写入选项 (如 metas, userIds); 每轮重试都会重新调用 transformFunction 拿到最新值
---@return Any 更新后的值， 放弃更新时返回 nil
---@return DataStoreKeyInfo 键信息
function DataStore:UpdateAsync(key, transformFunction) end

---DataStore:GetAsync 的可选参数。
---优先级高于 DataStore 初始化时的 DataStoreOptions，nil 字段表示继承实例默认值。
---**适用范围**: 仅服务端
---@class DataStoreGetOptions
---@field ExcludeDeleted Bool 是否排除已删除的条目 (可选)
---@field UpdateTimeAsc Bool 是否按更新时间升序排列 (可选)
---@field UseCache Bool 是否使用缓存 (可选)
---@field WithKeyInfo Bool 是否返回包含版本号、创建和修改日期、UserIds和Metas的类型为DataStoreKeyInfo 实例(可选)
DataStoreGetOptions = {}

---创建一个新的 DataStoreGetOptions 实例
---**适用范围**: 仅服务端
---@return DataStoreGetOptions
function DataStoreGetOptions.New() end

---DataStore:GetVersionAsync / GetVersionAtTimeAsync 的可选参数。
---优先级高于 DataStore 初始化时的 DataStoreOptions，nil 字段表示继承实例默认值。
---**适用范围**: 仅服务端
---@class DataStoreGetVersionOptions
---@field WithKeyInfo Bool 是否返回包含版本号、创建和修改日期、UserIds和Metas的类型为DataStoreKeyInfo 实例(可选)
DataStoreGetVersionOptions = {}

---创建一个新的 DataStoreGetVersionOptions 实例
---**适用范围**: 仅服务端
---@return DataStoreGetVersionOptions
function DataStoreGetVersionOptions.New() end

---DataStore:IncrementAsync 的可选参数。
---优先级高于 DataStore 初始化时的 DataStoreOptions，nil 字段表示继承实例默认值。
---**适用范围**: 仅服务端
---@class DataStoreIncrementOptions
---@field DefaultInitValue Int 当 key 不存在时的默认初始化值, 自增将在此基础上进行 (可选)
---@field DependPrevVersion String 依赖的前置版本号, 只有数据的当前版本与此版本一致时才允许自增 (可选)
---@field KeepOldMetas Bool 更新时是否保留旧元数据 (可选)
---@field WithKeyInfo Bool 是否返回包含版本号、创建和修改日期、UserIds和Metas的类型为DataStoreKeyInfo 实例(可选)
DataStoreIncrementOptions = {}

---添加单个用户ID
---**适用范围**: 仅服务端
---@param userId String 用户ID
function DataStoreIncrementOptions:AddUserId(userId) end

---获取用户自定义元数据字典
---**适用范围**: 仅服务端
---@return Table 元数据字典， 未设置时返回 nil
function DataStoreIncrementOptions:GetMetaDatas() end

---获取用户ID列表
---**适用范围**: 仅服务端
---@return Table 用户ID列表， 未设置时返回 nil
function DataStoreIncrementOptions:GetUserIds() end

---创建一个新的 DataStoreIncrementOptions 实例
---**适用范围**: 仅服务端
---@return DataStoreIncrementOptions
function DataStoreIncrementOptions.New() end

---设置单个用户自定义元数据
---**适用范围**: 仅服务端
---@param name String 元数据键名
---@param value String 元数据键值
function DataStoreIncrementOptions:SetMetaData(name, value) end

---整体替换用户自定义元数据字典
---**适用范围**: 仅服务端
---@param dict Table 元数据字典
function DataStoreIncrementOptions:SetMetaDatas(dict) end

---设置用户ID列表 (整体替换)
---**适用范围**: 仅服务端
---@param userIds Table 用户ID列表
function DataStoreIncrementOptions:SetUserIds(userIds) end

---合并更新用户自定义元数据, 已存在的 key 会被覆盖
---**适用范围**: 仅服务端
---@param dict Table 要合并的元数据
function DataStoreIncrementOptions:UpdateMetaDatas(dict) end

---DataStore 集合信息对象，从 ListDataStores 响应构造。
---不可实例化，仅由 DataStoreInfoPages 分页迭代产生。
---**适用范围**: 仅服务端
---@class DataStoreInfo
---@field CreatedTime Int 创建时间 (毫秒时间戳)
---@field DataStoreName String 集合名称
---@field DataStoreType Int 集合类型 (1=普通, 2=有序)
---@field IsDeleted Bool 是否已删除
---@field KeyCount Int 键数量
---@field Size Int 数据大小 (字节)
---@field UpdatedTime Int 更新时间 (毫秒时间戳)
local DataStoreInfo = {}

---DataStoreInfo 分页迭代器，由 DataStoreService:ListDataStoresAsync / ListOrderedDataStoresAsync 返回。
---GetCurrentPage() 返回 DataStoreInfo[]。
---**适用范围**: 仅服务端
---@class DataStoreInfoPages : Pages
local DataStoreInfoPages = {}

---DataStore 键简要信息对象，从 ListKeys 响应构造。
---不可实例化，仅由 DataStoreKeyBriefInfoPages 分页迭代产生。
---**适用范围**: 仅服务端
---@class DataStoreKeyBriefInfo
---@field IsDeleted Bool 是否已删除
---@field Key String 键名
---@field Scope String 前置域
local DataStoreKeyBriefInfo = {}

---DataStoreKeyBriefInfo 分页迭代器，由 DataStore:ListKeysAsync 返回。
---GetCurrentPage() 返回 DataStoreKeyBriefInfo[]。
---**适用范围**: 仅服务端
---@class DataStoreKeyBriefInfoPages : Pages
local DataStoreKeyBriefInfoPages = {}

---DataStore 键信息对象，从数据操作响应构造。
---不可实例化，仅由 DataStore:GetAsync / SetAsync / IncrementAsync / RemoveAsync / UpdateAsync 等方法返回。
---**适用范围**: 仅服务端
---@class DataStoreKeyInfo
---@field CreatedTime Int 创建时间 (毫秒时间戳)
---@field IsDeleted Bool 是否已删除
---@field Key String 键名
---@field Metas Table 用户自定义元数据
---@field Scope String 前置域
---@field UpdatedTime Int 更新时间 (毫秒时间戳)
---@field UserIds Table 用户ID列表
---@field Version String 版本号
local DataStoreKeyInfo = {}

---获取元数据字典
---**适用范围**: 仅服务端
---@return Table 元数据
function DataStoreKeyInfo:GetMetaDatas() end

---获取用户ID列表
---**适用范围**: 仅服务端
---@return Table 用户ID列表
function DataStoreKeyInfo:GetUserIds() end

---DataStore:ListKeysAsync 的可选参数。
---优先级高于 DataStore 初始化时的 DataStoreOptions，nil 字段表示继承实例默认值。
---**适用范围**: 仅服务端
---@class DataStoreListKeyOptions
---@field ExcludeDeleted Bool 是否排除已删除的条目 (可选)
DataStoreListKeyOptions = {}

---创建一个新的 DataStoreListKeyOptions 实例
---**适用范围**: 仅服务端
---@return DataStoreListKeyOptions
function DataStoreListKeyOptions.New() end

---DataStoreService:ListDataStoresAsync / ListOrderedDataStoresAsync 的可选参数。
---**适用范围**: 仅服务端
---@class DataStoreListOptions
---@field ExcludeDeleted Bool 是否排除已删除的 DataStore 集合 (可选)
DataStoreListOptions = {}

---创建一个新的 DataStoreListOptions 实例
---**适用范围**: 仅服务端
---@return DataStoreListOptions
function DataStoreListOptions.New() end

---DataStore 获取或列出存储集合的额外选项。
---在 DataStoreService:GetDataStore / GetOrderedDataStore 时传入，作为实例级默认值；各方法的 options 参数优先级高于此选项。
---**适用范围**: 仅服务端
---@class DataStoreOptions
---@field AllScopes Bool 是否跨范围查询
---@field ExcludeDeleted Bool 是否排除已删除的条目
---@field KeepOldMetas Bool 更新时是否保留旧元数据
---@field PermanentlyRemove Bool 是否永久删除 (而非软删除)
---@field UpdateTimeAsc Bool 是否按更新时间升序排列
---@field UseCache Bool 是否使用缓存
---@field WithKeyInfo Bool 是否返回包含版本号、创建和修改日期、UserIds和Metas的类型为DataStoreKeyInfo 实例
DataStoreOptions = {}

---创建一个新的 DataStoreOptions 实例
---**适用范围**: 仅服务端
---@return DataStoreOptions
function DataStoreOptions.New() end

---DataStore:RemoveAsync 的可选参数。
---优先级高于 DataStore 初始化时的 DataStoreOptions，nil 字段表示继承实例默认值。
---**适用范围**: 仅服务端
---@class DataStoreRemoveOptions
---@field DependPrevVersion String 依赖的前置版本号, 只有数据的当前版本与此版本一致时才允许删除 (可选)
---@field PermanentlyRemove Bool 是否永久删除 (而非软删除) (可选)
---@field WithKeyInfo Bool 是否返回包含版本号、创建和修改日期、UserIds和Metas的类型为DataStoreKeyInfo 实例(可选), 为 true 时若 key 不存在，则返回nil
DataStoreRemoveOptions = {}

---创建一个新的 DataStoreRemoveOptions 实例
---**适用范围**: 仅服务端
---@return DataStoreRemoveOptions
function DataStoreRemoveOptions.New() end

---DataStore:RemoveVersionAsync 的可选参数。
---优先级高于 DataStore 初始化时的 DataStoreOptions，nil 字段表示继承实例默认值。
---**适用范围**: 仅服务端
---@class DataStoreRemoveVersionOptions
---@field WithKeyInfo Bool 是否返回包含版本号、创建和修改日期、UserIds和Metas的类型为DataStoreKeyInfo 实例(可选), 为 true 时若版本不存在，则返回nil
DataStoreRemoveVersionOptions = {}

---创建一个新的 DataStoreRemoveVersionOptions 实例
---**适用范围**: 仅服务端
---@return DataStoreRemoveVersionOptions
function DataStoreRemoveVersionOptions.New() end

---DataStore:SetAsync 的可选参数。
---优先级高于 DataStore 初始化时的 DataStoreOptions，nil 字段表示继承实例默认值。
---**适用范围**: 仅服务端
---@class DataStoreSetOptions
---@field DependPrevVersion String 依赖的前置版本号, 只有数据的当前版本与此版本一致时才允许更新 (可选)
---@field KeepOldMetas Bool 更新时是否保留旧元数据 (可选)
---@field WithKeyInfo Bool 是否返回包含版本号、创建和修改日期、UserIds和Metas的类型为DataStoreKeyInfo 实例(可选)
DataStoreSetOptions = {}

---添加单个用户ID
---**适用范围**: 仅服务端
---@param userId String 用户ID
function DataStoreSetOptions:AddUserId(userId) end

---获取用户自定义元数据字典
---**适用范围**: 仅服务端
---@return Table 元数据字典， 未设置时返回 nil
function DataStoreSetOptions:GetMetaDatas() end

---获取用户ID列表
---**适用范围**: 仅服务端
---@return Table 用户ID列表， 未设置时返回 nil
function DataStoreSetOptions:GetUserIds() end

---创建一个新的 DataStoreSetOptions 实例
---**适用范围**: 仅服务端
---@return DataStoreSetOptions
function DataStoreSetOptions.New() end

---设置单个用户自定义元数据
---**适用范围**: 仅服务端
---@param name String 元数据键名
---@param value String 元数据键值
function DataStoreSetOptions:SetMetaData(name, value) end

---整体替换用户自定义元数据字典
---**适用范围**: 仅服务端
---@param dict Table 元数据字典
function DataStoreSetOptions:SetMetaDatas(dict) end

---设置用户ID列表 (整体替换)
---**适用范围**: 仅服务端
---@param userIds Table 用户ID列表
function DataStoreSetOptions:SetUserIds(userIds) end

---合并更新用户自定义元数据, 已存在的 key 会被覆盖
---**适用范围**: 仅服务端
---@param dict Table 要合并的元数据
function DataStoreSetOptions:UpdateMetaDatas(dict) end

---DataStore 版本信息对象（预留，待后端支持版本接口后完善）。
---不可实例化，仅由 DataStoreVersionInfoPages 分页迭代产生。
---**适用范围**: 仅服务端
---@class DataStoreVersionInfo
---@field CreatedTime Int 版本创建时间 (毫秒时间戳)
---@field IsDeleted Bool 是否已删除
---@field Version String 版本号
local DataStoreVersionInfo = {}

---DataStoreVersionInfo 分页迭代器，由 DataStore:ListVersionsAsync 返回。
---GetCurrentPage() 返回 DataStoreVersionInfo[]。
---**适用范围**: 仅服务端
---@class DataStoreVersionInfoPages : Pages
local DataStoreVersionInfoPages = {}

---EUIManager 用于管理 EUI 节点索引、事件同步与生命周期
---@class EUIManager
local EUIManager = {}

---创建 package UI 模块节点
---@param packageName String 包名
---@param uiModule String UI 模块名
---@return EUINodeBase 根节点(模块未注册时返回 nil)
function EUIManager:CreatePackageUIModuleNode(packageName, uiModule) end

---在指定坐标创建场景 UI 节点
---@param position Vector3 世界坐标
---@param nodeInfo? Any 节点信息
---@return EUISceneNode 场景 UI 节点
function EUIManager:CreateSceneNodeAtPosition(position, nodeInfo) end

---创建挂接到单位的场景 UI 节点
---@param Unit Unit 挂接单位
---@param Socket String 挂点名
---@param Offset Vector3 偏移
---@param InheritVisible Bool 跟随单位可见性
---@param nodeInfo? Any 节点信息
---@return EUISceneNode 场景 UI 节点
function EUIManager:CreateSceneNodeAttachUnit(Unit, Socket, Offset, InheritVisible, nodeInfo) end

---根据预设在指定坐标创建场景 UI
---@param prefabKey Int 预设 key
---@param position Vector3 世界坐标
---@return EUISceneNode 场景 UI 根节点
function EUIManager:CreateSceneUIByPrefabKeyAtPosition(prefabKey, position) end

---根据预设创建挂接到单位的场景 UI
---@param prefabKey Int 预设 key
---@param Unit Unit 挂接单位
---@param Socket String 挂点名
---@param Offset Vector3 偏移
---@param InheritVisible Bool 跟随单位可见性
---@return EUISceneNode 场景 UI 根节点
function EUIManager:CreateSceneUIByPrefabKeyAttachUnit(prefabKey, Unit, Socket, Offset, InheritVisible) end

---获取 package UI 模块的所有节点
---@param packageName String 包名
---@param uiModule String UI 模块名
---@return EUINodeBase[] 节点列表
function EUIManager:GetAllPackageNodes(packageName, uiModule) end

---获取屏幕分辨率
---@return Vector2 屏幕分辨率
function EUIManager:GetDeviceResolution() end

---获取指定 UnitType 的所有节点
---@param unitType String 单元类型(如 "EUIButton")
---@return EUINodeBase[] 匹配节点列表
function EUIManager:GetNodesByType(unitType) end

---获取 RootNode
---@return EUIRootNode 根节点
function EUIManager:GetRootNode() end

---EUI触摸交互参数
---**适用范围**: 客户端和服务端
---@class EUITouchInfo
---@field BeganPosition Vector2 触摸开始位置
---@field EndedPosition Vector2 触摸结束位置
---@field MovedPosition Vector2 触摸移动位置
---@field TouchID Int 触摸ID
local EUITouchInfo = {}

---特效绑定数据
---@class EffectBindData
---@field BindOffset Vector3 绑定位置偏移
---@field BindSocket String 绑定点（socket）
---@field BindType Enums.EffectBindType 绑定类型
---@field BindUnitId Int 绑定单位
EffectBindData = {}

---蛋形生物的外观数据，描述蛋仔的盲盒、染色、时装散件、配饰、脸型、表情、肤色、蛋皮等可换装外观信息，并提供运行时换装、挂接外观件、显示头顶气泡与表情等表现能力。
---@class EggyAppearance
local EggyAppearance = {}

---在指定骨骼挂点上挂接外观件
---@param appearanceId String 外观ID
---@param socket Enums.SkeletalSocketType 绑定点
---@param offset Vector3 位置偏移
---@param rot Quaternion 旋转
---@param scale Vector3 缩放
---@return Int 绑定ID
function EggyAppearance:BindAppearance(appearanceId, socket, offset, rot, scale) end

---设置是否启用头顶气泡消息
---@param enable Bool 是否启用
function EggyAppearance:EnableBubbleMessage(enable) end

---获取指定挂点的配饰ID
---@param bindPos Enums.AccessoryBindType 配饰挂点
---@return Int 配饰ID
function EggyAppearance:GetAccessoryId(bindPos) end

---获取蛋皮
---@return Int 蛋皮ID
function EggyAppearance:GetEggShellId() end

---获取静态脸型
---@return Int 面部表情编号
function EggyAppearance:GetFaceId() end

---获取动态表情
---@return Enums.FaceStatus 动态表情
function EggyAppearance:GetFaceStatus() end

---获取指定部位的时装散件ID
---@param partType Enums.FashionPartType 时装部位
---@return Int 时装散件ID
function EggyAppearance:GetFashionPart(partType) end

---获取肤色
---@return Int 肤色ID
function EggyAppearance:GetSkinColorId() end

---隐藏当前的气泡消息
function EggyAppearance:HideBubbleMessage() end

---重置时装和模型外观
function EggyAppearance:ResetAppearance() end

---解除所有挂接的外观件
function EggyAppearance:ResetBindAppearance() end

---设置时装配饰
---@param accessoryId Int 配饰ID
function EggyAppearance:SetAccessoryId(accessoryId) end

---按生物预设整体切换外观
---@param assetId String 生物预设ID
function EggyAppearance:SetAppearanceByAssetId(assetId) end

---设置蛋皮
---@param eggShellId Int 蛋皮ID
function EggyAppearance:SetEggShellId(eggShellId) end

---设置静态脸型
---@param faceId Int 面部表情编号
function EggyAppearance:SetFaceId(faceId) end

---切换动态表情
---@param faceStatus Enums.FaceStatus 动态表情编号
function EggyAppearance:SetFaceStatus(faceStatus) end

---设置时装部位
---@param partId Int 时装部位ID
function EggyAppearance:SetFashionPart(partId) end

---设置肤色
---@param skinColorId Int 肤色ID
function EggyAppearance:SetSkinColorId(skinColorId) end

---在角色头顶显示文字气泡消息
---@param message String 气泡消息
---@param duration Float 持续时间(可选)
---@param hideDistance? Float 隐藏距离(可选)
function EggyAppearance:ShowBubbleMessage(message, duration, hideDistance) end

---解除指定挂接的外观件
---@param bindId Int 绑定ID
---@return Bool 是否成功
function EggyAppearance:UnbindAppearance(bindId) end

---面集合
---@class Faces
---@field Back Bool 背面
---@field Bottom Bool 底面
---@field Front Bool 正面
---@field Left Bool 左面
---@field Right Bool 右面
---@field Top Bool 顶面
Faces = {}

---可选名称：Right | Top | Back | Left | Bottom | Front
---**适用范围**: 客户端和服务端
---@param ... String 面名称（可变参数）
---@return Faces
function Faces.New(...) end

---UserInputService 各输入事件与查询接口带出的用户输入数据，承载本次输入的按键、类型、状态、位置与变化量等信息。
---@class InputObject
---@field Delta Vector3 相对上一帧的输入变化量
---@field KeyCode Enums.KeyCode 本次输入对应的键盘按键代码
---@field Position Vector3 输入位置（屏幕坐标系）
---@field Processed Bool 该输入是否已被引擎/UI 层处理
---@field UserInputState Enums.UserInputState 本次输入的状态（开始、变化、结束等）
---@field UserInputType Enums.UserInputType 本次输入的来源类型（键盘、鼠标、触摸等）
local InputObject = {}

---Player 加入战斗相关的信息。通过Player:GetJoinData接口获取。
---@class JoinData
---@field Members String[] 与该玩家一起被传送过来的其他玩家列表
---@field SourceMapId String 玩家传送来源的地图编号
---@field TeleportData Any 传送时，使用TeleportOptions:SetTeleportData接口设置的传送附带数据。
local JoinData = {}

---LogService:GetLogHistory 返回的单条历史日志记录
---@class LogRecord
---@field Context Table 结构化上下文数据
---@field Message string 日志消息内容
---@field MessageType Enums.MessageType 日志类型枚举值
---@field Timestamp Float 写入历史时的服务器时间，单位秒。此值为服务器时区时间。
local LogRecord = {}

---材质参数用于控制单位表面材质的各项表现属性，涵盖粗糙度、金属度、自发光、水体、贴花、细节纹理、边缘光等模块。
---@class MaterialParam
---@field MaterialAlpha Float 材质整体不透明度，0 为完全透明、1 为完全不透明。
---@field MaterialBorderColor Color 边缘光的颜色。仅在“开启边缘光”开启时生效。
---@field MaterialBorderIntensity Float 边缘光的亮度倍率。仅在“开启边缘光”开启时生效。
---@field MaterialBorderScale Float 边缘光的覆盖范围（菲涅尔角度）。仅在“开启边缘光”开启时生效。
---@field MaterialCullMode Int 材质的面剔除模式。未配置时保持材质组原始设置。
---@field MaterialDecalAngle Float 纹理的旋转角度（度）。
---@field MaterialDecalIsFreeScaling Bool 开启后可对纹理 X/Y 轴单独设置缩放，关闭时使用整体缩放。
---@field MaterialDecalOffsetX Float 纹理沿 X 轴方向的偏移量。
---@field MaterialDecalOffsetY Float 纹理沿 Y 轴方向的偏移量。
---@field MaterialDecalRepeatX Float 纹理沿 X 轴的单独缩放比例。仅在“纹理自由缩放”开启时生效。
---@field MaterialDecalRepeatY Float 纹理沿 Y 轴的单独缩放比例。仅在“纹理自由缩放”开启时生效。
---@field MaterialDepthContrast Float 水体深浅区域颜色的过渡平滑度。
---@field MaterialDepthScale Float 水体的视觉深度，影响深浅区域的过渡与颜色变化。
---@field MaterialDisturbanceParmW Float 第二组波纹的朝向。
---@field MaterialDisturbanceParmX Float 第二组波纹的起伏幅度。
---@field MaterialDisturbanceParmY Float 第二组波纹的密度。
---@field MaterialDisturbanceParmZ Float 第二组波纹的动画播放速度。
---@field MaterialEdgeWeaken Float 靠近岸边时波浪起伏的弱化程度。
---@field MaterialEdgeWidth Float 岸边波浪弱化效果的影响范围。
---@field MaterialEmissiveColor Color 材质整体自发光的颜色。
---@field MaterialEmissiveIntensity1 Float 染色区域1的自发光亮度倍率。
---@field MaterialEmissiveIntensity2 Float 染色区域2的自发光亮度倍率。
---@field MaterialEmissiveIntensity3 Float 染色区域3的自发光亮度倍率。
---@field MaterialEmissiveIntensity4 Float 染色区域4的自发光亮度倍率。
---@field MaterialEnableBorder Bool 是否开启轮廓边缘发光效果（菲涅尔效果）。
---@field MaterialEnableRipples Bool 是否开启水面涟漪效果。
---@field MaterialEnableTiling Bool 开启后，采用三面映射纹理；关闭时，采用模型本身的UV。
---@field MaterialFlowSpeed Float 表面波纹纹理沿 UV 方向的流动速度。
---@field MaterialFoamEmis Float 岸边浮沫的自发光亮度。
---@field MaterialFoamSpeed Float 水面浮沫扰动的动画播放速度。
---@field MaterialFoamStep Float 岸边浮沫与水面的过渡平滑度。
---@field MaterialFoamStrength Float 岸边浮沫的扰动幅度。
---@field MaterialFoamWidth Float 岸边浮沫的覆盖宽度。
---@field MaterialGradientAxis Float 颜色渐变所沿的坐标轴方向，0 为 X 轴、1 为 Y 轴、2 为 Z 轴。
---@field MaterialGradientCenter Float 渐变在所选轴向上的中心位置。
---@field MaterialGradientContrast Float 两种颜色间渐变的过渡对比度，0 为完全混为一种颜色，1 为不过渡有一条直线边界。
---@field MaterialIconColor Color 附带贴花的整体染色颜色，需要材质上带有附带贴花。
---@field MaterialIntensityA Float 材质整体自发光的亮度倍率，0 表示不发光。
---@field MaterialIntensityB Float 材质整体金属度。0 表示非金属（绝缘体），1 表示完全金属。仅在“金属度局部调整”关闭时生效。
---@field MaterialIntensityG Float 材质整体表面粗糙度。值越小表面越光滑、反射越聚集；值越大越粗糙、反射越发散。仅在“粗糙度局部调整”关闭时生效。
---@field MaterialMetalness1 Float 染色区域1的局部金属度。仅在“金属度局部调整”开启时生效。
---@field MaterialMetalness2 Float 染色区域2的局部金属度。仅在“金属度局部调整”开启时生效。
---@field MaterialMetalness3 Float 染色区域3的局部金属度。仅在“金属度局部调整”开启时生效。
---@field MaterialMetalness4 Float 染色区域4的局部金属度。仅在“金属度局部调整”开启时生效。
---@field MaterialNoiseSpeed Float 噪声波形的动画播放速度。
---@field MaterialOffsetScale Float 云层扰动的密度，控制云表面扰动发生的细致程度。
---@field MaterialOffsetSpeed Float 云层扰动的动画播放速度。
---@field MaterialOffsetStrength Float 云层扰动的幅度，0 表示无扰动。
---@field MaterialOpacityMax Float 水体的最大不透明度，值越大水体越浑浊，值越小越清澈。
---@field MaterialPatternAngle Float 细节纹理的旋转角度（度）。
---@field MaterialPatternColor Color 细节纹理的颜色。
---@field MaterialPatternColorKey Float 细节纹理被细节颜色染色的程度，0 表示完全去色；部分或完全去色可更大程度使用细节纹理的法线效果，可以叠加出有特色的质感。
---@field MaterialPatternDepth Float 细节纹理的视差/凹凸深度，0 表示无凹凸。
---@field MaterialPatternEmissive Float 细节纹理的自发光亮度倍率。
---@field MaterialPatternMetalness Float 细节纹理区域的金属度。
---@field MaterialPatternOffsetX Float 细节纹理沿 X 轴方向的偏移量。
---@field MaterialPatternOffsetY Float 细节纹理沿 Y 轴方向的偏移量。
---@field MaterialPatternOp Float 细节纹理的透明度，0 表示细节纹理完全透光。
---@field MaterialPatternRepeatX Float 细节纹理沿 X 轴方向的缩放程度。
---@field MaterialPatternRepeatY Float 细节纹理沿 Y 轴方向的缩放程度。
---@field MaterialPatternRoughness Float 细节纹理区域的粗糙度。
---@field MaterialPatternTexture String 细节纹理使用的贴图资源。
---@field MaterialPatternUV Bool 开启后细节纹理使用世界坐标 UV，移动模型时，纹理维持在世界空间中的位置不变，从而看起来在模型表面的位置有变化，而非模型局部 UV。只读属性。
---@field MaterialReflectScope Float 水面反射的范围/模糊程度。
---@field MaterialReflectStrength Float 水面环境反射的强度。
---@field MaterialRepeatScale Float 纹理的整体缩放比例。仅在“纹理自由缩放”关闭时生效。
---@field MaterialRippleDensity Float 水面波浪的整体密集程度。
---@field MaterialRipplesIntensity Float 涟漪的起伏幅度。
---@field MaterialRipplesScale Float 涟漪的密集程度。
---@field MaterialRipplesScope Float 涟漪效果的影响范围。
---@field MaterialRoughness1 Float 染色区域1的局部粗糙度。仅在“粗糙度局部调整”开启时生效。
---@field MaterialRoughness2 Float 染色区域2的局部粗糙度。仅在“粗糙度局部调整”开启时生效。
---@field MaterialRoughness3 Float 染色区域3的局部粗糙度。仅在“粗糙度局部调整”开启时生效。
---@field MaterialRoughness4 Float 染色区域4的局部粗糙度。仅在“粗糙度局部调整”开启时生效。
---@field MaterialSFoamBrightness Float 水面浮沫的覆盖范围。
---@field MaterialSFoamContrast Float 水面浮沫的过渡对比度。
---@field MaterialSFoamTiling Float 水面浮沫纹理的密度。
---@field MaterialSFoamType Float 水面浮沫的形状类型。
---@field MaterialTransparentMode Int 材质的透明/贴图渲染模式。未配置时保持材质组原始设置。
---@field MaterialUVtilingX Float 波纹沿表面 X 轴方向的纹理重复次数。
---@field MaterialUVtilingY Float 波纹沿表面 Y 轴方向的纹理重复次数。
---@field MaterialUseMetalness4 Bool 开启后可对4个染色区域分别设置金属度，关闭时使用整体金属度。
---@field MaterialUseRoughness4 Bool 开启后可对4个染色区域分别设置粗糙度，关闭时使用整体粗糙度。
---@field MaterialWaterIntensityW Float 水体的自发光强度。
---@field MaterialWaterIntensityX Float 水面波浪整体的起伏幅度。
---@field MaterialWaterIntensityY Float 水面波浪整体的朝向角度（度）。
---@field MaterialWaterIntensityZ Float 水体的金属度。
---@field MaterialWaveIntensity Float 顶点扰动的幅度，0 表示无顶点偏移。
---@field MaterialWaveLightDensity Float 水面波光的密集程度。
---@field MaterialWaveLightScale Float 水面波光的大小。
---@field MaterialWaveLightScope Float 水面波光的覆盖范围。
---@field MaterialWaveLightSpeed Float 水面波光的动画播放速度。
---@field MaterialWaveLightStrength Float 水面波光的发光亮度倍率。
---@field MaterialWaveSpeed Float 顶点扰动动画的播放速度，值越大波动越快。
---@field MaterialWaveformParmW Float 第一组波纹的朝向。
---@field MaterialWaveformParmX Float 第一组波纹的起伏幅度。
---@field MaterialWaveformParmY Float 第一组波纹的密度。
---@field MaterialWaveformParmZ Float 第一组波纹的动画播放速度。
MaterialParam = {}

---创建一个材质参数（MaterialParam）；传入属性表时按属性名初始化各材质属性（与 CreateData('MaterialParam', {...}) 一致），省略时使用默认数据创建。
---**适用范围**: 客户端和服务端
---@param initData? Table 初始属性表
---@return MaterialParam
function MaterialParam.New(initData) end

---4x4 矩阵，用于表示齐次变换
---@class Matrix
---@field Forward Vector3 前方向
---@field Pitch Float 俯仰角（ZXY 顺序，弧度）
---@field Right Vector3 右方向
---@field Roll Float 翻滚角（ZXY 顺序，弧度）
---@field Rotation Quaternion 旋转分量
---@field Scale Vector3 缩放分量
---@field Translation Vector3 平移分量
---@field Up Vector3 上方向
---@field Yaw Float 偏航角（ZXY 顺序，弧度）
Matrix = {}

---对向量应用矩阵变换
---@param v Vector3
---@return Vector3
function Matrix:Apply(v) end

---从欧拉角创建旋转矩阵（ZXY 旋转顺序）
---**适用范围**: 客户端和服务端
---@param x Float Pitch（弧度）
---@param y Float Yaw（弧度）
---@param z Float Roll（弧度）
---@return Matrix
function Matrix.FromEulerAngles(x, y, z) end

---返回逆矩阵副本
---@return Matrix
function Matrix:GetInverse() end

---返回单位矩阵（无平移、无旋转、缩放为1）
---**适用范围**: 客户端和服务端
---@return Matrix
function Matrix.Identity() end

---矩阵求逆
---@return Matrix
function Matrix:Inverse() end

---原地构造为朝向旋转（基于 forward/up）
---@param forward Vector3
---@param up Vector3
function Matrix:MakeOrient(forward, up) end

---原地构造为轴角旋转
---@param axis Vector3
---@param angle Float
function Matrix:MakeRotation(axis, angle) end

---原地构造为「from→to」对齐旋转
---@param from Vector3
---@param to Vector3
function Matrix:MakeRotationBetween(from, to) end

---原地构造为绕 X 轴的旋转
---@param angle Float
function Matrix:MakeRotationX(angle) end

---原地构造为绕 Y 轴的旋转
---@param angle Float
function Matrix:MakeRotationY(angle) end

---原地构造为绕 Z 轴的旋转
---@param angle Float
function Matrix:MakeRotationZ(angle) end

---由 TRS 构造 4x4 矩阵
---**适用范围**: 客户端和服务端
---@param translation Vector3
---@param rotation Quaternion
---@param scale Vector3
---@return Matrix
function Matrix.New(translation, rotation, scale) end

---矩阵求转置
---@return Matrix
function Matrix:Transpose() end

---返回零矩阵（无平移、无旋转、缩放为0）
---**适用范围**: 客户端和服务端
---@return Matrix
function Matrix.Zero() end

---3x3 矩阵
---@class Matrix3x3
Matrix3x3 = {}

---矩阵乘向量
---@param v Vector3
---@return Vector3
function Matrix3x3:Apply(v) end

---克隆矩阵
---@return Matrix3x3
function Matrix3x3:Clone() end

---为叉积构造反对称矩阵
---**适用范围**: 客户端和服务端
---@param v Vector3
---@return Matrix3x3
function Matrix3x3.ComputeSkewSymmetricMatrixForCrossProduct(v) end

---逐元素取绝对值后的矩阵
---@return Matrix3x3
function Matrix3x3:GetAbsoluteMatrix() end

---获取指定列（0-based）
---@param col Int
---@return Vector3
function Matrix3x3:GetColumn(col) end

---获取行列式
---@return Float
function Matrix3x3:GetDeterminant() end

---获取逆矩阵
---@return Matrix3x3
function Matrix3x3:GetInverse() end

---获取指定行（0-based）
---@param row Int
---@return Vector3
function Matrix3x3:GetRow(row) end

---获取矩阵的迹
---@return Float
function Matrix3x3:GetTrace() end

---获取转置矩阵
---@return Matrix3x3
function Matrix3x3:GetTranspose() end

---返回单位矩阵
---**适用范围**: 客户端和服务端
---@return Matrix3x3
function Matrix3x3.Identity() end

---创建 3x3 矩阵（9 个参数，行主序）
---**适用范围**: 客户端和服务端
---@param m00 Float
---@param m01 Float
---@param m02 Float
---@param m10 Float
---@param m11 Float
---@param m12 Float
---@param m20 Float
---@param m21 Float
---@param m22 Float
---@return Matrix3x3
function Matrix3x3.New(m00, m01, m02, m10, m11, m12, m20, m21, m22) end

---设置全部矩阵元素
---@param m00 Float
---@param m01 Float
---@param m02 Float
---@param m10 Float
---@param m11 Float
---@param m12 Float
---@param m20 Float
---@param m21 Float
---@param m22 Float
function Matrix3x3:SetAllValues(m00, m01, m02, m10, m11, m12, m20, m21, m22) end

---设置为单位矩阵
function Matrix3x3:SetToIdentity() end

---将矩阵清零
function Matrix3x3:SetToZero() end

---返回零矩阵
---**适用范围**: 客户端和服务端
---@return Matrix3x3
function Matrix3x3.Zero() end

---MemoryStore 哈希集合。
---不可实例化，仅由 MemoryStoreService:GetHashMap(name) 返回。
---**适用范围**: 仅服务端
---@class MemoryStoreHashMap
local MemoryStoreHashMap = {}

---删除整个集合
---**适用范围**: 仅服务端
function MemoryStoreHashMap:DeleteAsync() end

---获取指定 key 的数据
---**适用范围**: 仅服务端
---@param key String 键名
---@return Any 键不存在时返回 nil
function MemoryStoreHashMap:GetAsync(key) end

---分页列出所有 items
---**适用范围**: 仅服务端
---@param count Int 每页数量
---@return MemoryStoreHashMapPages 分页迭代器
function MemoryStoreHashMap:ListItemsAsync(count) end

---删除指定 key
---**适用范围**: 仅服务端
---@param key String 键名
function MemoryStoreHashMap:RemoveAsync(key) end

---设置指定 key 的数据
---**适用范围**: 仅服务端
---@param key String 键名
---@param value Any 数据值 (INCR 模式下需为数字)
---@param options? MemoryStoreHashMapSetOptions 可选参数, 可通过 game:CreateData("MemoryStoreHashMapSetOptions") 创建
---@return Any 成功返回写入的 value 或 INCR 累加后的值; 命中条件失败返回 nil
function MemoryStoreHashMap:SetAsync(key, value, options) end

---CAS 原子更新: 先读后写; 最多重试 5 次
---**适用范围**: 仅服务端
---@param key String 键名
---@param transformFunction function 变换函数 (oldValue) → newValue, options?
---@return Any 更新后的值; transform 返回 nil 时为 nil
function MemoryStoreHashMap:UpdateAsync(key, transformFunction) end

---MemoryStoreHashMap 分页迭代器，由 MemoryStoreHashMap:ListItemsAsync 返回。
---GetCurrentPage() 返回 {Key: String, Value: Any}[]。
---**适用范围**: 仅服务端
---@class MemoryStoreHashMapPages : Pages
local MemoryStoreHashMapPages = {}

---MemoryStoreHashMap:SetAsync 的可选参数。
---所有字段默认 nil，表示未显式设置则采用默认行为。
---**适用范围**: 仅服务端
---@class MemoryStoreHashMapSetOptions
---@field EQT Any 仅当旧 value 等于指定值时更新 (可选)
---@field EX Int 以秒为单位的生存时间 (可选)
---@field EXAT Int 以秒为单位的绝对生存时间 (可选)
---@field GT Bool 仅当新旧 value 都为数值且新值大于当前值时更新 (可选)
---@field GTE Bool 仅当新旧 value 都为数值且新值大于等于当前值时更新 (可选)
---@field GTET Float 仅当旧 value 大于等于指定值时更新 (可选)
---@field GTT Float 仅当旧 value 大于指定值时更新 (可选)
---@field INCR Bool 累加而非覆盖 value, 要求新旧值均为数值 (可选)
---@field KEEPTTL Bool 保留现有键的生存时间 (可选)
---@field LT Bool 仅当新旧 value 都为数值且新值小于当前值时更新 (可选)
---@field LTE Bool 仅当新旧 value 都为数值且新值小于等于当前值时更新 (可选)
---@field LTET Float 仅当旧 value 小于等于指定值时更新 (可选)
---@field LTT Float 仅当旧 value 小于指定值时更新 (可选)
---@field NEQT Any 仅当旧 value 不等于指定值时更新 (可选)
---@field NX Bool 仅当键不存在时设置 (可选)
---@field PX Int 以毫秒为单位的生存时间 (可选)
---@field PXAT Int 以毫秒为单位的绝对生存时间 (可选)
---@field XX Bool 仅当键存在时设置 (可选)
MemoryStoreHashMapSetOptions = {}

---创建一个新的 MemoryStoreHashMapSetOptions 实例
---**适用范围**: 仅服务端
---@return MemoryStoreHashMapSetOptions
function MemoryStoreHashMapSetOptions.New() end

---MemoryStoreHashMap:UpdateAsync 在 transform 中返回的可选参数。
---只接受不影响原子更新正确性的字段：value 阈值比较和 TTL 控制。
---**适用范围**: 仅服务端
---@class MemoryStoreHashMapUpdateOptions
---@field EQT Any 仅当旧 value 等于指定值时更新 (可选)
---@field EX Int 以秒为单位的生存时间 (可选)
---@field EXAT Int 以秒为单位的绝对生存时间 (可选)
---@field GTET Float 仅当旧 value 大于等于指定值时更新 (可选)
---@field GTT Float 仅当旧 value 大于指定值时更新 (可选)
---@field KEEPTTL Bool 保留现有键的生存时间 (可选)
---@field LTET Float 仅当旧 value 小于等于指定值时更新 (可选)
---@field LTT Float 仅当旧 value 小于指定值时更新 (可选)
---@field NEQT Any 仅当旧 value 不等于指定值时更新 (可选)
---@field PX Int 以毫秒为单位的生存时间 (可选)
---@field PXAT Int 以毫秒为单位的绝对生存时间 (可选)
MemoryStoreHashMapUpdateOptions = {}

---创建一个新的 MemoryStoreHashMapUpdateOptions 实例
---**适用范围**: 仅服务端
---@return MemoryStoreHashMapUpdateOptions
function MemoryStoreHashMapUpdateOptions.New() end

---MemoryStore 队列集合。
---不可实例化，仅由 MemoryStoreService:GetQueue(name, queueInvisibleExpireSecs?) 返回。
---**适用范围**: 仅服务端
---@class MemoryStoreQueue
local MemoryStoreQueue = {}

---入队
---**适用范围**: 仅服务端
---@param value Any 队列项数据
---@param priority? Int 优先级, 默认 0
---@param options? MemoryStoreQueueAddOptions 可选参数, 可通过 game:CreateData("MemoryStoreQueueAddOptions") 创建
---@return String 成功返回 itemId; 命中条件失败返回 nil
function MemoryStoreQueue:AddAsync(value, priority, options) end

---删除整个队列
---**适用范围**: 仅服务端
function MemoryStoreQueue:DeleteAsync() end

---查询队列大小
---**适用范围**: 仅服务端
---@param options? MemoryStoreQueueGetSizeOptions 可选参数, 可通过 game:CreateData("MemoryStoreQueueGetSizeOptions") 创建
---@return Int 队列大小
function MemoryStoreQueue:GetSizeAsync(options) end

---出队读取 (含 WaitTimeout 长轮询)
---**适用范围**: 仅服务端
---@param count Int 期望读取的项目数
---@param options? MemoryStoreQueueReadOptions 可选参数, 可通过 game:CreateData("MemoryStoreQueueReadOptions") 创建
---@return String 本批读取标识; 超时/空队列时返回 nil
---@return Table [{ItemId， Value}， ...]; 超时/空队列时返回 nil
function MemoryStoreQueue:ReadAsync(count, options) end

---按 readId 批量删除已读取的项
---**适用范围**: 仅服务端
---@param readId String 批次读取标识
function MemoryStoreQueue:RemoveAsync(readId) end

---按 itemId 单项删除
---**适用范围**: 仅服务端
---@param itemId String 项 id
function MemoryStoreQueue:RemoveByItemIdAsync(itemId) end

---MemoryStoreQueue:AddAsync 的可选参数。
---所有字段默认 nil，表示未显式设置则采用默认行为。
---**适用范围**: 仅服务端
---@class MemoryStoreQueueAddOptions
---@field EX Int 以秒为单位的生存时间 (可选)
---@field EXAT Int 以秒为单位的绝对生存时间 (可选)
---@field MSNX Bool 仅当整个 MemoryStore 不存在时设置 (可选)
---@field MSXX Bool 仅当整个 MemoryStore 存在时设置 (可选)
---@field PX Int 以毫秒为单位的生存时间 (可选)
---@field PXAT Int 以毫秒为单位的绝对生存时间 (可选)
MemoryStoreQueueAddOptions = {}

---创建一个新的 MemoryStoreQueueAddOptions 实例
---**适用范围**: 仅服务端
---@return MemoryStoreQueueAddOptions
function MemoryStoreQueueAddOptions.New() end

---MemoryStoreQueue:GetSizeAsync 的可选参数。
---所有字段默认 nil，表示未显式设置则采用默认行为。
---**适用范围**: 仅服务端
---@class MemoryStoreQueueGetSizeOptions
---@field ExcludeInvisible Bool 排除不可见的元素 (可选)
MemoryStoreQueueGetSizeOptions = {}

---创建一个新的 MemoryStoreQueueGetSizeOptions 实例
---**适用范围**: 仅服务端
---@return MemoryStoreQueueGetSizeOptions
function MemoryStoreQueueGetSizeOptions.New() end

---MemoryStoreQueue:ReadAsync 的可选参数。
---所有字段默认 nil，表示未显式设置则采用默认行为。
---**适用范围**: 仅服务端
---@class MemoryStoreQueueReadOptions
---@field AllOrNothing Bool 所有操作要么全部成功要么全部失败, 默认 false (可选)
---@field QueueInvisibleExpireSecs Int 队列不可见元素过期时间 单位秒, 默认 30 (可选)
---@field WaitTimeout Int 等待超时时间 单位秒, -1 表示无限等待, 默认 -1 (可选)
MemoryStoreQueueReadOptions = {}

---创建一个新的 MemoryStoreQueueReadOptions 实例
---**适用范围**: 仅服务端
---@return MemoryStoreQueueReadOptions
function MemoryStoreQueueReadOptions.New() end

---MemoryStore 有序集合。排序规则：排序键优先于键进行排序。数字排序键首先排序，其次是字符串排序键，最后是没有排序键的项。
---不可实例化，仅由 MemoryStoreService:GetSortedMap(name) 返回。
---**适用范围**: 仅服务端
---@class MemoryStoreSortedMap
local MemoryStoreSortedMap = {}

---删除整个集合
---**适用范围**: 仅服务端
function MemoryStoreSortedMap:DeleteAsync() end

---获取指定 key 的数据
---**适用范围**: 仅服务端
---@param key String 键名
---@return Any 键不存在时返回 nil
---@return Any 排序键; 键不存在时返回 nil
function MemoryStoreSortedMap:GetAsync(key) end

---范围分页查询
---**适用范围**: 仅服务端
---@param direction Int 排序方向, 使用 SortDirection.Ascending(1) / SortDirection.Descending(-1)
---@param count Int 每页数量
---@param options? MemoryStoreSortedMapGetRangeOptions 可选参数, 可通过 game:CreateData("MemoryStoreSortedMapGetRangeOptions") 创建
---@return MemoryStoreSortedMapPages 分页迭代器
function MemoryStoreSortedMap:GetRangeAsync(direction, count, options) end

---查询集合元素数量
---**适用范围**: 仅服务端
---@return Int 元素数量
function MemoryStoreSortedMap:GetSizeAsync() end

---删除指定 key
---**适用范围**: 仅服务端
---@param key String 键名
function MemoryStoreSortedMap:RemoveAsync(key) end

---设置指定 key 的数据
---**适用范围**: 仅服务端
---@param key String 键名
---@param value Any 数据值
---@param sortKey? Any 排序键, 可为数字/字符串/nil
---@param options? MemoryStoreSortedMapSetOptions 可选参数 (条件修饰/TTL 等), 可通过 game:CreateData("MemoryStoreSortedMapSetOptions") 创建
---@return Any 成功返回写入的 value; 命中条件失败返回 nil
---@return Any 成功返回写入的 sortKey
function MemoryStoreSortedMap:SetAsync(key, value, sortKey, options) end

---CAS 原子更新: 先读后写, 支持 sortKey 变换; 最多重试 5 次
---**适用范围**: 仅服务端
---@param key String 键名
---@param transformFunction function 变换函数 (oldValue, oldSortKey) → newValue, newSortKey?, options?
---@param sortKey? Any 初始 sortKey 兜底 (仅在键首次创建时生效)
---@return Any 更新后的值; transform 返回 nil 时为 nil
---@return Any 更新后的 sortKey; transform 返回 nil 时为 nil
function MemoryStoreSortedMap:UpdateAsync(key, transformFunction, sortKey) end

---MemoryStoreSortedMap:GetRangeAsync 的可选参数。
---所有字段默认 nil，表示未显式设置则采用默认行为。
---**适用范围**: 仅服务端
---@class MemoryStoreSortedMapGetRangeOptions
---@field LowerBoundKey String 返回键的下限, 排除自身在外 (可选)
---@field LowerBoundSortKey String 返回排序键的下限, 排除自身在外 (可选)
---@field UpperBoundKey String 返回键的上限, 排除自身在外 (可选)
---@field UpperBoundSortKey String 返回排序键的上限, 排除自身在外 (可选)
MemoryStoreSortedMapGetRangeOptions = {}

---创建一个新的 MemoryStoreSortedMapGetRangeOptions 实例
---**适用范围**: 仅服务端
---@return MemoryStoreSortedMapGetRangeOptions
function MemoryStoreSortedMapGetRangeOptions.New() end

---MemoryStoreSortedMap 分页迭代器，由 MemoryStoreSortedMap:GetRangeAsync 返回。
---GetCurrentPage() 返回 {Key: String, Value: Any, SortKey: Any}[]。
---**适用范围**: 仅服务端
---@class MemoryStoreSortedMapPages : Pages
local MemoryStoreSortedMapPages = {}

---MemoryStoreSortedMap:SetAsync 的可选参数。
---所有字段默认 nil，表示未显式设置则采用默认行为。
---**适用范围**: 仅服务端
---@class MemoryStoreSortedMapSetOptions
---@field EQT Float 仅当旧 sortKey 等于指定值时更新 (可选)
---@field EX Int 以秒为单位的生存时间 (可选)
---@field EXAT Int 以秒为单位的绝对生存时间 (可选)
---@field GT Bool 仅当新旧 sortKey 都为数值且新值大于当前值时更新 (可选)
---@field GTE Bool 仅当新旧 sortKey 都为数值且新值大于等于当前值时更新 (可选)
---@field GTET Float 仅当旧 sortKey 大于等于指定值时更新 (可选)
---@field GTT Float 仅当旧 sortKey 大于指定值时更新 (可选)
---@field INCR Bool 累加而非覆盖 sortKey, 要求新旧值均为数值 (可选)
---@field KEEPTTL Bool 保留现有键的生存时间 (可选)
---@field LT Bool 仅当新旧 sortKey 都为数值且新值小于当前值时更新 (可选)
---@field LTE Bool 仅当新旧 sortKey 都为数值且新值小于等于当前值时更新 (可选)
---@field LTET Float 仅当旧 sortKey 小于等于指定值时更新 (可选)
---@field LTT Float 仅当旧 sortKey 小于指定值时更新 (可选)
---@field MSNX Bool 仅当整个 MemoryStore 不存在时设置 (可选)
---@field MSXX Bool 仅当整个 MemoryStore 存在时设置 (可选)
---@field NEQT Float 仅当旧 sortKey 不等于指定值时更新 (可选)
---@field NX Bool 仅当键不存在时设置 (可选)
---@field PX Int 以毫秒为单位的生存时间 (可选)
---@field PXAT Int 以毫秒为单位的绝对生存时间 (可选)
---@field XX Bool 仅当键存在时设置 (可选)
MemoryStoreSortedMapSetOptions = {}

---创建一个新的 MemoryStoreSortedMapSetOptions 实例
---**适用范围**: 仅服务端
---@return MemoryStoreSortedMapSetOptions
function MemoryStoreSortedMapSetOptions.New() end

---MemoryStoreSortedMap:UpdateAsync 在 transform 中返回的可选参数。
---只接受不影响原子更新正确性的字段：sortKey 阈值比较和 TTL 控制。
---**适用范围**: 仅服务端
---@class MemoryStoreSortedMapUpdateOptions
---@field EQT Float 仅当旧 sortKey 等于指定值时更新 (可选)
---@field EX Int 以秒为单位的生存时间 (可选)
---@field EXAT Int 以秒为单位的绝对生存时间 (可选)
---@field GTET Float 仅当旧 sortKey 大于等于指定值时更新 (可选)
---@field GTT Float 仅当旧 sortKey 大于指定值时更新 (可选)
---@field KEEPTTL Bool 保留现有键的生存时间 (可选)
---@field LTET Float 仅当旧 sortKey 小于等于指定值时更新 (可选)
---@field LTT Float 仅当旧 sortKey 小于指定值时更新 (可选)
---@field NEQT Float 仅当旧 sortKey 不等于指定值时更新 (可选)
---@field PX Int 以毫秒为单位的生存时间 (可选)
---@field PXAT Int 以毫秒为单位的绝对生存时间 (可选)
MemoryStoreSortedMapUpdateOptions = {}

---创建一个新的 MemoryStoreSortedMapUpdateOptions 实例
---**适用范围**: 仅服务端
---@return MemoryStoreSortedMapUpdateOptions
function MemoryStoreSortedMapUpdateOptions.New() end

---数值范围
---@class NumberRange
---@field Max Float 最大值
---@field Min Float 最小值
NumberRange = {}

---创建 NumberRange
---**适用范围**: 客户端和服务端
---@param min Float
---@param max Float
---@return NumberRange
function NumberRange.New(min, max) end

---数值序列
---@class NumberSequence
---@field Keypoints NumberSequenceKeypoint[] 关键帧列表
NumberSequence = {}

---创建数值序列
---**适用范围**: 客户端和服务端
---@param value Any 数值或关键帧数组
---@return NumberSequence
function NumberSequence.New(value) end

---数值序列关键帧
---@class NumberSequenceKeypoint
---@field Envelope Float 包络
---@field Time Float 时间
---@field Value Float 值
NumberSequenceKeypoint = {}

---创建关键帧
---**适用范围**: 客户端和服务端
---@param time Float
---@param value Float
---@param envelope? Float
---@return NumberSequenceKeypoint
function NumberSequenceKeypoint.New(time, value, envelope) end

---有序数据存储集合，继承自 DataStore，添加 GetSortedAsync 方法；值必须是整数。
---不可实例化，仅由 DataStoreService:GetOrderedDataStore() 返回。
---**适用范围**: 仅服务端
---@class OrderedDataStore : DataStore
local OrderedDataStore = {}

---按 value 排序获取有序存储的数据
---**适用范围**: 仅服务端
---@param ascending Bool 是否升序
---@param pageSize? Int 页大小, 默认 0 (使用服务端默认值)
---@param minValue? Int 最小值过滤, 包含
---@param maxValue? Int 最大值过滤, 包含
---@param options? DataStoreGetOptions 可选参数, 优先级高于 OrderedDataStore 初始化时的 DataStoreOptions, 可通过 DataStoreGetOptions.New() 创建
---@return OrderedDataStoreKeyValueInfoPages 分页迭代器
function OrderedDataStore:GetSortedAsync(ascending, pageSize, minValue, maxValue, options) end

---有序数据存储键值对信息对象，从 GetSorted 响应构造。
---不可实例化，仅由 OrderedDataStoreKeyValueInfoPages 分页迭代产生。
---**适用范围**: 仅服务端
---@class OrderedDataStoreKeyValueInfo
---@field Key String 键名
---@field Scope String 前置域
---@field UpdatedTime Int 更新时间 (毫秒时间戳)
---@field Value Int 值 (整数)
local OrderedDataStoreKeyValueInfo = {}

---OrderedDataStoreKeyValueInfo 分页迭代器，由 OrderedDataStore:GetSortedAsync 返回。
---GetCurrentPage() 返回 OrderedDataStoreKeyValueInfo[]。
---**适用范围**: 仅服务端
---@class OrderedDataStoreKeyValueInfoPages : Pages
local OrderedDataStoreKeyValueInfoPages = {}

---PhysicsService 空间重叠查询 (GetPartBoundsInBox / GetPartBoundsInRadius / GetPartsInPart) 的过滤参数
---@class OverlapParams
---@field CollisionGroup String 碰撞组名称, 不设置则使用默认碰撞组(不过滤)
---@field FilterDescendantsInstances Unit[] 与 FilterType 配合的 Unit 数组, 默认空数组
---@field FilterType Int Exclude (默认, 跳过 FilterDescendantsInstances 列表中的 Unit), Include (仅返回列表中的 Unit)
---@field MaxParts Int 0 表示无限制 (默认), 否则限制返回 Unit 数量
OverlapParams = {}

---创建 OverlapParams
---**适用范围**: 客户端和服务端
---@return OverlapParams
function OverlapParams.New() end

---分页迭代器基类，提供通用的分页数据访问能力。
---业务方不可直接构造，仅能由各 ListXxxAsync 方法返回对应的子类实例。
---**适用范围**: 仅服务端
---@class Pages
---@field IsFinished Bool 是否已迭代完毕
local Pages = {}

---翻到下一页 (异步方法)
---**适用范围**: 仅服务端
---@return Bool 是否成功翻页
function Pages:AdvanceToNextPageAsync() end

---获取当前页数据
---**适用范围**: 仅服务端
---@return String[] 当前页的数据对象列表
function Pages:GetCurrentPage() end

---寻路射线检测结果
---**适用范围**: 客户端和服务端
---@class PathHitInfo
---@field EndPosition Vector3 射线终点坐标
---@field HitPosition Vector3 碰撞点的世界坐标，未命中时为 nil
---@field HitT Float 碰撞点在射线上的插值参数（0~1），未命中时无意义
---@field IsHit Bool 是否与导航网格发生碰撞
---@field StartPosition Vector3 射线起点坐标
local PathHitInfo = {}

---寻路路点
---**适用范围**: 客户端和服务端
---@class PathWaypoint
---@field Action Enums.PathWaypointAction 到达该路点时执行的动作
---@field Label String 路点的自定义标签
---@field Position Vector3 路点的世界坐标位置
local PathWaypoint = {}

---物理材质属性（密度、摩擦、弹性）
---@class PhysicalProperties
---@field Density Float 密度 (kg/stud³)
---@field Elasticity Float 弹性/恢复系数
---@field ElasticityWeight Float 弹性混合权重
---@field Friction Float 摩擦系数
---@field FrictionWeight Float 摩擦混合权重
PhysicalProperties = {}

---创建一个新的物理材质属性实例
---@param values? Table 创建参数: Density(密度), Friction(摩擦系数), Elasticity(弹性系数), FrictionWeight(摩擦混合权重), ElasticityWeight(弹性混合权重)
---@return PhysicalProperties
function PhysicalProperties.New(values) end

---PlayerGui 管理玩家的 ScreenGui/EuiManager 等，并支持注册/解注册本地自定义事件，通过 player.PlayerGui 获取
---@class PlayerGui
---@field EuiManager EUIManager EUI 管理器
---@field ScreenGui ScreenGui 玩家屏幕 Gui，提供飘字提示、游戏结果/结束面板、观战控件显隐、个人/团队积分面板等显隐控制
local PlayerGui = {}

---四元数，用于表示旋转
---@class Quaternion
---@field Euler Vector3 欧拉角（弧度，ZXY 顺序）
---@field Pitch Float 俯仰角（弧度，ZXY 顺序）
---@field Roll Float 翻滚角（弧度，ZXY 顺序）
---@field Yaw Float 偏航角（弧度，ZXY 顺序）
---@field w Float W 分量
---@field x Float X 分量
---@field y Float Y 分量
---@field z Float Z 分量
Quaternion = {}

---将四元数旋转应用到向量
---@param v Vector3
---@return Vector3
function Quaternion:Apply(v) end

---四元数点积
---@param rhs Quaternion
---@return Float
function Quaternion:Dot(rhs) end

---从轴角创建四元数
---**适用范围**: 客户端和服务端
---@param axis Vector3 旋转轴（应为单位向量）
---@param angle Float 旋转角度（弧度）
---@return Quaternion
function Quaternion.FromAxisAngle(axis, angle) end

---从欧拉角创建四元数（ZXY 旋转顺序）
---**适用范围**: 客户端和服务端
---@param x Float Pitch（弧度）
---@param y Float Yaw（弧度）
---@param z Float Roll（弧度）
---@return Quaternion
function Quaternion.FromEulerAngles(x, y, z) end

---返回共轭四元数
---@return Quaternion
function Quaternion:GetConjugate() end

---获取前向向量
---@return Vector3
function Quaternion:GetForward() end

---返回逆四元数
---@return Quaternion
function Quaternion:GetInverse() end

---返回对应的 3x3 旋转矩阵
---@return Matrix3x3
function Quaternion:GetMatrix() end

---获取俯仰角
---@return Float
function Quaternion:GetPitch() end

---获取右向向量
---@return Vector3
function Quaternion:GetRight() end

---获取翻滚角
---@return Float
function Quaternion:GetRoll() end

---获取旋转角度和轴，返回 Vector4(axisX, axisY, axisZ, angle)
---@return Vector4
function Quaternion:GetRotationAngleAxis() end

---返回单位四元数
---@return Quaternion
function Quaternion:GetUnit() end

---获取上向向量
---@return Vector3
function Quaternion:GetUp() end

---返回四元数的向量部分 (x, y, z)
---@return Vector3
function Quaternion:GetVectorV() end

---获取偏航角
---@return Float
function Quaternion:GetYaw() end

---返回单位四元数 (0, 0, 0, 1)
---**适用范围**: 客户端和服务端
---@return Quaternion
function Quaternion.Identity() end

---就地求逆
function Quaternion:Inverse() end

---判断值是否为有限数
---@return Bool
function Quaternion:IsFinite() end

---判断是否为单位四元数
---@return Bool
function Quaternion:IsUnit() end

---判断是否为有效四元数（有限且单位）
---@return Bool
function Quaternion:IsValid() end

---四元数长度
---@return Float
function Quaternion:Length() end

---四元数长度的平方
---@return Float
function Quaternion:LengthSquare() end

---创建一个新的四元数
---**适用范围**: 客户端和服务端
---@param x Float
---@param y Float
---@param z Float
---@param w Float
---@return Quaternion
function Quaternion.New(x, y, z, w) end

---归一化线性插值
---**适用范围**: 客户端和服务端
---@param a Quaternion
---@param b Quaternion
---@param t Float 插值因子 [0, 1]
---@return Quaternion
function Quaternion.Nlerp(a, b, t) end

---四元数归一化
function Quaternion:Normalize() end

---将四元数设置为单位四元数
function Quaternion:SetToIdentity() end

---球面线性插值
---**适用范围**: 客户端和服务端
---@param a Quaternion
---@param b Quaternion
---@param t Float 插值因子 [0, 1]
---@return Quaternion
function Quaternion.Slerp(a, b, t) end

---射线（起点 + 方向向量）
---@class Ray
---@field Direction Vector3 方向向量
---@field Origin Vector3 起点
---@field Unit Ray 方向归一化后的射线
Ray = {}

---获取射线上离目标点最近的点
---@param point Vector3
---@return Vector3
function Ray:ClosestPoint(point) end

---获取点到射线的最短距离
---@param point Vector3
---@return Float
function Ray:Distance(point) end

---创建射线
---**适用范围**: 客户端和服务端
---@param origin Vector3
---@param direction Vector3
---@return Ray
function Ray.New(origin, direction) end

---PhysicsService:Raycast/Spherecast/Blockcast/Shapecast 的过滤参数
---@class RaycastParams
---@field CollisionGroup String 碰撞组名称, 用于按碰撞关系过滤, nil 表示不过滤
---@field FilterDescendantsInstances Unit[] 与 FilterType 配合的 Unit 数组, 默认空数组
---@field FilterType Int Exclude (默认, 跳过 FilterDescendantsInstances 列表中的 Unit), Include (仅返回列表中的 Unit)
---@field TargetCollisionGroupList String[] 显式指定射线命中的目标碰撞组列表, 优先级高于 CollisionGroup。非空时直接 OR 各组的 category 位作为目标掩码; 空列表回退到 CollisionGroup 自身组关系掩码
RaycastParams = {}

---创建 RaycastParams
---**适用范围**: 客户端和服务端
---@return RaycastParams
function RaycastParams.New() end

---PhysicsService 射线/形状投射返回的命中结果。未命中时返回 nil。
---@class RaycastResult
---@field Distance Float 从射线/形状起点到命中点的距离
---@field Instance Unit 被射线/形状投射命中的 Unit 实例
---@field Normal Vector3 命中点处表面的法线方向
---@field Position Vector3 射线/形状与物体表面的交点世界坐标
local RaycastResult = {}

---矩形
---@class Rect
---@field Height Float 高度
---@field Max Vector2 右下角
---@field Min Vector2 左上角
---@field Width Float 宽度
Rect = {}

---创建矩形
---**适用范围**: 客户端和服务端
---@param minX Float
---@param minY Float
---@param maxX Float
---@param maxY Float
---@return Rect
function Rect.New(minX, minY, maxX, maxY) end

---轴对齐 3D 区域
---@class Region3
---@field Size Vector3 区域尺寸
Region3 = {}

---按格子大小扩展
---@param resolution Float
---@return Region3
function Region3:ExpandToGrid(resolution) end

---创建 Region3
---**适用范围**: 客户端和服务端
---@param min Vector3
---@param max Vector3
---@return Region3
function Region3.New(min, max) end

---16 位整数 3D 区域
---@class Region3int16
---@field Max Vector3int16 最大角
---@field Min Vector3int16 最小角
Region3int16 = {}

---创建 Region3int16
---**适用范围**: 客户端和服务端
---@param min Vector3int16
---@param max Vector3int16
---@return Region3int16
function Region3int16.New(min, max) end

---远程事件，用于客户端与服务端之间的异步单向通信，可由服务端发送给指定客户端或所有客户端，也可由客户端发送给服务端。
---**适用范围**: 客户端和服务端
---@class RemoteEvent
---@field OnClientEvent Signal<fun(args?: Any)> 客户端监听服务端消息的信号。回调参数：args 事件参数
---@field OnServerEvent Signal<fun(player: Player, args?: Any)> 服务端监听客户端消息的信号。回调参数：player 触发事件的玩家, args 事件参数
RemoteEvent = {}

---从服务端发送事件给所有客户端
---**适用范围**: 客户端和服务端
---@param args? Any 事件参数
function RemoteEvent:FireAllClients(args) end

---从服务端发送事件给指定玩家客户端
---**适用范围**: 客户端和服务端
---@param player Player 目标玩家
---@param args? Any 事件参数
function RemoteEvent:FireClient(player, args) end

---从客户端发送事件给服务端
---**适用范围**: 客户端和服务端
---@param args? Any 事件参数
function RemoteEvent:FireServer(args) end

---RemoteEvent.New(EventName)创建一个新的远程事件实例，用于客户端与服务端之间的异步单向通信
---**适用范围**: 客户端和服务端
---@param eventName String 事件名称，用于标识该远程事件
---@return RemoteEvent 新创建的 RemoteEvent 实例
function RemoteEvent.New(eventName) end

---预留服务器结果, 由 TeleportService:ReserveServerAsync 返回
---@class ReserveServerResult
---@field ReservedServerAccessCode String 预留服务器战场实例访问码 (可填入 TeleportOptions.ReservedServerAccessCode 用于实际传送)
local ReserveServerResult = {}

---玩家屏幕 Gui，管理和控制玩家本地内置的 2D UI。提供一组内置面板与提示的显隐控制，包括飘字提示、游戏结果/结束面板、观战角色操作控件显隐，以及个人与团队积分面板的显示与更新。通过 player.PlayerGui.ScreenGui 获取
---**适用范围**: 仅客户端
---@class ScreenGui
local ScreenGui = {}

---隐藏个人积分面板
---**适用范围**: 仅客户端
function ScreenGui:HidePlayerScoreBoard() end

---隐藏团队积分面板
---**适用范围**: 仅客户端
function ScreenGui:HideTeamScoreBoard() end

---观战时隐藏 / 恢复角色操作控件（复位、左摇杆、跳/翻滚/冲刺、技能等）
---**适用范围**: 仅客户端
---@param hidden Bool true=隐藏（进入观战），false=恢复（退出观战）
function ScreenGui:SetSpectatorControlsHidden(hidden) end

---设置阵营颜色
---**适用范围**: 仅客户端
---@param campId Int 阵营 ID
---@param color Int 颜色值 (0xRRGGBB)
function ScreenGui:SetTeamColor(campId, color) end

---显示游戏结束面板
---**适用范围**: 仅客户端
function ScreenGui:ShowGameOverPanel() end

---显示游戏结果面板
---**适用范围**: 仅客户端
---@param result Bool 游戏结果（胜负）
function ScreenGui:ShowGameResult(result) end

---显示个人积分面板
---**适用范围**: 仅客户端
---@param score Int 当前积分
---@param targetScore Int 目标积分（0=不显示目标）
function ScreenGui:ShowPlayerScoreBoard(score, targetScore) end

---显示团队积分面板
---**适用范围**: 仅客户端
---@param campScores Table 阵营积分映射，键为阵营 ID（Int），值为积分（Int）
function ScreenGui:ShowTeamScoreBoard(campScores) end

---在屏幕上显示一条飘字提示消息
---**适用范围**: 仅客户端
---@param msg String 消息字符串
---@param duration Float 持续时间（秒），不传时默认 1.0
function ScreenGui:ShowTips(msg, duration) end

---模拟屏幕滑动
---**适用范围**: 仅客户端
---@param startPos Vector2 起始坐标
---@param endPos Vector2 结束坐标
---@param duration Float 滑动时长（秒），不传时默认 0.3
function ScreenGui:SimulateSwipe(startPos, endPos, duration) end

---模拟屏幕点击
---**适用范围**: 仅客户端
---@param position Vector2 坐标
function ScreenGui:SimulateTap(position) end

---截取当前屏幕并保存为 PNG 图片
---**适用范围**: 仅客户端
function ScreenGui:TakeScreenshot() end

---更新个人积分显示
---**适用范围**: 仅客户端
---@param score Int 当前积分
function ScreenGui:UpdatePlayerScore(score) end

---更新阵营积分（全量数据）
---**适用范围**: 仅客户端
---@param campScores Table 阵营积分映射，键为阵营 ID（Int），值为积分（Int）
function ScreenGui:UpdateTeamScore(campScores) end

---事件信号，用于同端内部模块之间的发布订阅通信，支持持续监听、单次监听以及触发并向所有监听者转发参数；如需跨端通信请使用 RemoteEvent。
---**适用范围**: 客户端和服务端
---@class Signal
Signal = {}

---连接监听函数
---**适用范围**: 客户端和服务端
---@param func function 事件触发时调用的监听函数
---@return Connection 可用于断开监听的连接句柄
function Signal:Connect(func) end

---触发信号并向监听函数转发参数
---**适用范围**: 客户端和服务端
---@param args? Any 事件参数
function Signal:Fire(args) end

---Signal.New()创建一个新的事件信号实例，用于同端内部模块之间的发布订阅通信
---**适用范围**: 客户端和服务端
---@return Signal 新创建的 Signal 实例
function Signal.New() end

---连接只触发一次的监听函数
---**适用范围**: 客户端和服务端
---@param func function 第一次事件触发时调用的监听函数
---@return Connection 可用于提前断开监听的连接句柄
function Signal:Once(func) end

---皮肤槽位
---@class SkinSlot
---@field ModelColor1 Color 模型染色区域1的颜色
---@field ModelColor2 Color 模型染色区域2的颜色
---@field ModelColor3 Color 模型染色区域3的颜色
---@field ModelColor4 Color 模型染色区域4的颜色
---@field SkinId String 皮肤
local SkinSlot = {}

---子自定义外观数据，自定义外观（CustomAppearance）中一个子模型的外观描述；记录子模型的模型资源、皮肤、染色区域、挂点、相对主模型的位置/旋转/缩放、材质参数、透明度与阴影投射等属性。仅作为 CustomAppearance 的 SubAppearance（子模型）数组元素使用。
---@class SubCustomAppearance
---@field CastShadow Bool 子模型是否投射阴影。
---@field MaterialParam MaterialParam 子模型的材质参数，用于调整模型的材质表现。
---@field MaterialParamList MaterialParam[] 与 SkinSlots 按索引平行对应的逐槽位材质参数；槽位元素为空时回落该槽位皮肤自带的材质参数。
---@field ModelAlpha Float 子模型的透明度，取值 0（完全透明）~ 1（不透明）。
---@field ModelColor1 Color 子模型染色区域 1 的颜色；仅当模型支持该染色区域时生效。
---@field ModelColor2 Color 子模型染色区域 2 的颜色；仅当模型支持该染色区域时生效。
---@field ModelColor3 Color 子模型染色区域 3 的颜色；仅当模型支持该染色区域时生效。
---@field ModelColor4 Color 子模型染色区域 4 的颜色；仅当模型支持该染色区域时生效。
---@field Offset Vector3 子模型相对主模型的位置偏移。
---@field RenderMeshId String 子模型使用的模型资源（Mesh）。
---@field Rotation Quaternion 子模型相对主模型的旋转（四元数）。
---@field Scale Vector3 子模型相对主模型的缩放。
---@field SkinId String 子模型应用的皮肤；为空时不设置皮肤。
---@field SocketName String 子模型挂接到主模型的挂点名称；为空时为默认挂点（仅主模型为蛋形生物时生效）。
SubCustomAppearance = {}

---创建一个子自定义外观（SubCustomAppearance）；传入属性表时按属性名初始化各属性（与 CreateData('SubCustomAppearance', {...}) 一致），省略时使用默认数据创建。创建后可添加到 CustomAppearance 的 SubAppearance 数组中。
---**适用范围**: 客户端和服务端
---@param initData? Table 初始属性表
---@return SubCustomAppearance
function SubCustomAppearance.New(initData) end

---传送异步结果, 由 TeleportService:TeleportAsync 在传入 teleportOptions 时返回
---@class TeleportAsyncResult
---@field ReservedServerAccessCode String 预留服务器战场实例访问码
local TeleportAsyncResult = {}

---传送选项, 在 TeleportService:TeleportAsync 时传入, 控制传送行为。通过 TeleportService:CreateTeleportOptions() 创建实例
---@class TeleportOptions
---@field ReservedServerAccessCode String 预留服务器战场实例访问码, 可以通过 TeleportService:ReserveServerAsync 或者 TeleportService:ApplyIngameMatchAsync 获取
---@field ServerInstanceId String 服务器战场实例ID (用于前往指定实例, 如好友的服务器)；只能用于前往当前运行中的实例
---@field ShouldReserveServer Bool 是否创建一个新的服务器战场实例, 默认 true
TeleportOptions = {}

---获取传送附带数据
---@return Any 传送附带数据， 未设置时返回 nil
function TeleportOptions:GetTeleportData() end

---创建一个新的 TeleportOptions 实例
---@return TeleportOptions
function TeleportOptions.New() end

---设置传送附带数据(会一并传到目标地图的接收端）。通过Player:GetJoinData接口获取。
---@param teleportData Any 任意 Lua 数据
function TeleportOptions:SetTeleportData(teleportData) end

---计时器对象，由 TimerService:CreateTimer 创建
---@class Timer
---@field OnEvent Signal 计时器触发事件
local Timer = {}

---取消计时器
function Timer:Cancel() end

---获取计时器间隔时间（秒）
---@return Float 间隔时间（秒）
function Timer:GetTimerInterval() end

---获取计时器剩余触发次数
---@return Int 剩余次数
function Timer:GetTimerRemain() end

---检查计时器是否正在运行
---@return Bool 是否正在运行
function Timer:IsRunning() end

---暂停计时器
function Timer:Pause() end

---从暂停中恢复计时器
function Timer:Resume() end

---启动计时器
function Timer:Start() end

---TRS 变换（位移/旋转/缩放）
---@class Transform
---@field LookVector Vector3 前向向量
---@field Position Vector3 位移（别名）
---@field RightVector Vector3 右向量
---@field Rotation Quaternion 旋转
---@field Scale Vector3 缩放
---@field Translation Vector3 位移
---@field UpVector Vector3 上向量
Transform = {}

---对一个点应用变换
---@param point Vector3
---@return Vector3
function Transform:Apply(point) end

---对一个方向向量应用变换（忽略平移）
---@param dir Vector3
---@return Vector3
function Transform:ApplyDirection(dir) end

---从轴角创建 Transform
---**适用范围**: 客户端和服务端
---@param axis Vector3
---@param angle Float
---@return Transform
function Transform.FromAxisAngle(axis, angle) end

---从欧拉角创建纯旋转 Transform（ZXY 旋转顺序）
---**适用范围**: 客户端和服务端
---@param rx Float
---@param ry Float
---@param rz Float
---@return Transform
function Transform.FromEulerAngles(rx, ry, rz) end

---从 4x4 矩阵创建 Transform
---**适用范围**: 客户端和服务端
---@param matrix Matrix
---@return Transform
function Transform.FromMatrix(matrix) end

---近似相等比较
---@param other Transform
---@param epsilon Float
---@return Bool
function Transform:FuzzyEq(other, epsilon) end

---获取逆 Transform
---@return Transform
function Transform:GetInverse() end

---获取旋转
---@return Quaternion
function Transform:GetOrientation() end

---获取位置
---@return Vector3
function Transform:GetPosition() end

---返回单位 Transform
---**适用范围**: 客户端和服务端
---@return Transform
function Transform.Identity() end

---插值两个 Transform
---**适用范围**: 客户端和服务端
---@param a Transform
---@param b Transform
---@param t Float 插值因子 [0, 1]
---@return Transform
function Transform.InterpolateTransforms(a, b, t) end

---获取逆 Transform
---@return Transform
function Transform:Inverse() end

---判断是否为有效 Transform
---@return Bool
function Transform:IsValid() end

---线性插值
---@param goal Transform
---@param alpha Float
---@return Transform
function Transform:Lerp(goal, alpha) end

---构造朝向目标点的 Transform
---**适用范围**: 客户端和服务端
---@param at Vector3
---@param lookAt Vector3
---@param up Vector3
---@return Transform
function Transform.LookAt(at, lookAt, up) end

---创建一个 Transform
---**适用范围**: 客户端和服务端
---@param translation Vector3
---@param rotation Quaternion
---@param scale? Vector3 缩放（默认 (1,1,1)）
---@return Transform
function Transform.New(translation, rotation, scale) end

---将世界空间点转换到本地空间
---@param v Vector3
---@return Vector3
function Transform:PointToObjectSpace(v) end

---将本地空间点转换到世界空间
---@param v Vector3
---@return Vector3
function Transform:PointToWorldSpace(v) end

---设置旋转
---@param quat Quaternion
function Transform:SetOrientation(quat) end

---设置位置
---@param pos Vector3
function Transform:SetPosition(pos) end

---设置为单位 Transform
function Transform:SetToIdentity() end

---转为 4x4 矩阵
---@return Matrix
function Transform:ToMatrix() end

---将世界空间 Transform 转换到本地空间
---@param cf Transform
---@return Transform
function Transform:ToObjectSpace(cf) end

---将本地空间 Transform 转换到世界空间
---@param cf Transform
---@return Transform
function Transform:ToWorldSpace(cf) end

---组合变换：返回 self * other（先 other，再 self）
---@param other Transform
---@return Transform
function Transform:Transform(other) end

---将世界空间方向转换到本地空间
---@param v Vector3
---@return Vector3
function Transform:VectorToObjectSpace(v) end

---将本地空间方向转换到世界空间
---@param v Vector3
---@return Vector3
function Transform:VectorToWorldSpace(v) end

---TriggerUnit本地触发回调信息
---**适用范围**: 客户端和服务端
---@class TriggerCallbackInfo
---@field OtherUnit Unit 进入或离开触发区域的另一个单位
local TriggerCallbackInfo = {}

---TweenInfo 补间动画配置
---@class TweenInfo
---@field DelayTime Float 延迟时间（秒）
---@field Duration Float 动画持续时间（秒）
---@field EasingDirection Enums.EasingDirection 缓动方向
---@field EasingStyle Enums.EasingStyle 缓动风格
---@field RepeatCount Int 重复次数（0=一次，-1=无限）
---@field Reverses Bool 是否反向播放
TweenInfo = {}

---创建 TweenInfo 对象
---**适用范围**: 客户端和服务端
---@param duration Float 持续时间
---@param easingStyle? Int 缓动风格, 默认 0 (Linear)
---@param easingDirection? Int 缓动方向, 默认 0 (In)
---@param repeatCount? Int 重复次数, 默认 0 (0=一次, -1=无限)
---@param reverses? Bool 反向播放, 默认 false
---@param delayTime? Float 延迟时间, 默认 0
---@return TweenInfo TweenInfo 对象
function TweenInfo.New(duration, easingStyle, easingDirection, repeatCount, reverses, delayTime) end

---UDim（一维 UI 尺寸）
---@class UDim
---@field Offset Int 偏移分量
---@field Scale Float 比例分量
UDim = {}

---创建 UDim
---**适用范围**: 客户端和服务端
---@param scale Float
---@param offset Int
---@return UDim
function UDim.New(scale, offset) end

---UDim2（二维 UI 尺寸）
---@class UDim2
---@field Height UDim 高度（y 别名）
---@field Width UDim 宽度（x 别名）
---@field x UDim X 轴
---@field y UDim Y 轴
UDim2 = {}

---从 Offset 创建
---**适用范围**: 客户端和服务端
---@param x Int
---@param y Int
---@return UDim2
function UDim2.FromOffset(x, y) end

---从 Scale 创建
---**适用范围**: 客户端和服务端
---@param x Float
---@param y Float
---@return UDim2
function UDim2.FromScale(x, y) end

---线性插值
---@param other UDim2
---@param alpha Float
---@return UDim2
function UDim2:Lerp(other, alpha) end

---创建 UDim2
---**适用范围**: 客户端和服务端
---@param xScale Float
---@param xOffset Int
---@param yScale Float
---@param yOffset Int
---@return UDim2
function UDim2.New(xScale, xOffset, yScale, yOffset) end

---二维向量
---@class Vector2
---@field Magnitude Float 向量长度
---@field Unit Vector2 单位向量
---@field x Float X 坐标
---@field y Float Y 坐标
Vector2 = {}

---逐分量取绝对值
---@return Vector2
function Vector2:Abs() end

---两个向量之间的有符号夹角（弧度），符号由二维叉积决定
---@param other Vector2
---@return Float
function Vector2:Angle(other) end

---逐分量向上取整
---@return Vector2
function Vector2:Ceil() end

---二维叉积（返回标量）
---@param other Vector2
---@return Float
function Vector2:Cross(other) end

---二维叉积别名（兼容旧代码）
---@param other Vector2
---@return Float
function Vector2:Cross2d(other) end

---点积
---@param other Vector2
---@return Float
function Vector2:Dot(other) end

---逐分量向下取整
---@return Vector2
function Vector2:Floor() end

---近似相等比较
---@param other Vector2
---@param epsilon Float 允许的误差范围
---@return Bool
function Vector2:FuzzyEq(other, epsilon) end

---线性插值
---@param goal Vector2
---@param alpha Float 插值因子 [0, 1]
---@return Vector2
function Vector2:Lerp(goal, alpha) end

---逐分量取最大值
---@param others Vector2
---@return Vector2
function Vector2:Max(others) end

---逐分量取最小值
---@param others Vector2
---@return Vector2
function Vector2:Min(others) end

---创建一个新的 Vector2
---**适用范围**: 客户端和服务端
---@param x Float X 坐标
---@param y Float Y 坐标
---@return Vector2
function Vector2.New(x, y) end

---向量归一化（就地修改），返回归一化后的向量
---@return Vector2
function Vector2:Normalize() end

---逐分量取符号
---@return Vector2
function Vector2:Sign() end

---16 位整数二维向量
---@class Vector2int16
---@field x Int X 分量
---@field y Int Y 分量
Vector2int16 = {}

---创建 Vector2int16
---**适用范围**: 客户端和服务端
---@param x Int
---@param y Int
---@return Vector2int16
function Vector2int16.New(x, y) end

---三维向量，用于表示位置、方向等
---@class Vector3
---@field Magnitude Float 向量长度
---@field Pitch Float 俯仰角（弧度，由方向向量推算）
---@field Unit Vector3 单位向量
---@field Yaw Float 偏航角（弧度，由方向向量推算）
---@field x Float X 坐标
---@field y Float Y 坐标
---@field z Float Z 坐标
Vector3 = {}

---逐分量取绝对值
---@return Vector3
function Vector3:Abs() end

---计算两个向量之间的角度（弧度）
---@param other Vector3
---@return Float
function Vector3:Angle(other) end

---逐分量向上取整
---@return Vector3
function Vector3:Ceil() end

---叉积
---@param other Vector3
---@return Vector3
function Vector3:Cross(other) end

---点积
---@param other Vector3
---@return Float
function Vector3:Dot(other) end

---逐分量向下取整
---@return Vector3
function Vector3:Floor() end

---近似相等比较
---@param other Vector3
---@param epsilon Float 允许的误差范围
---@return Bool
function Vector3:FuzzyEq(other, epsilon) end

---向量长度
---@return Float
function Vector3:Length() end

---线性插值
---@param goal Vector3
---@param alpha Float 插值因子 [0, 1]
---@return Vector3
function Vector3:Lerp(goal, alpha) end

---逐分量取最大值
---@param others Vector3
---@return Vector3
function Vector3:Max(others) end

---逐分量取最小值
---@param others Vector3
---@return Vector3
function Vector3:Min(others) end

---创建一个新的 Vector3
---**适用范围**: 客户端和服务端
---@param x Float
---@param y Float
---@param z Float
---@return Vector3
function Vector3.New(x, y, z) end

---向量归一化（就地修改），返回归一化后的向量
---@return Vector3
function Vector3:Normalize() end

---逐分量取符号
---@return Vector3
function Vector3:Sign() end

---16 位整数三维向量
---@class Vector3int16
---@field x Int X 分量
---@field y Int Y 分量
---@field z Int Z 分量
Vector3int16 = {}

---创建 Vector3int16
---**适用范围**: 客户端和服务端
---@param x Int
---@param y Int
---@param z Int
---@return Vector3int16
function Vector3int16.New(x, y, z) end

---四维向量
---@class Vector4
---@field Magnitude Float 向量长度
---@field Unit Vector4 单位向量
---@field w Float W 坐标
---@field x Float X 坐标
---@field y Float Y 坐标
---@field z Float Z 坐标
Vector4 = {}

---点积
---@param rhs Vector4
---@return Float
function Vector4:Dot(rhs) end

---逐分量取绝对值
---@return Vector4
function Vector4:GetAbsoluteVector() end

---获取最大分量值
---@return Float
function Vector4:GetMaxValue() end

---获取最小分量值
---@return Float
function Vector4:GetMinValue() end

---返回单位向量
---@return Vector4
function Vector4:GetUnit() end

---向量长度
---@return Float
function Vector4:Length() end

---创建一个新的 Vector4
---**适用范围**: 客户端和服务端
---@param x Float
---@param y Float
---@param z Float
---@param w Float
---@return Vector4
function Vector4.New(x, y, z, w) end

---向量归一化（就地修改），返回归一化后的向量
---@return Vector4
function Vector4:Normalize() end

--========================== 枚举 Enum ==========================

---所有枚举的命名空间
Enums = {}

---蛋仔配饰的挂接部位，分为头部、腰部和背部，用于标识配饰所佩戴的位置。
---@enum Enums.AccessoryBindType 
Enums.AccessoryBindType = {
	Head = 1,  ---头部
	Waist = 2,  ---腰部
	Back = 3,  ---背部
}

---ActivePayerStatus 玩家在体验中的付费状态枚举
---@enum Enums.ActivePayerStatus 
Enums.ActivePayerStatus = {
	Unknown = 0,  ---数据不可用
	Never = 1,  ---玩家在该体验中从未消费过
	Lapsed = 2,  ---玩家曾经消费过，但目前不是活跃付费用户
	Casual50Percent = 3,  ---消费排名 51-100%（低消费玩家）
	Intermediate35Percent = 4,  ---消费排名 16-50%（中等消费）
	Top15Percent = 5,  ---消费排名 1-15%（顶级消费）
}

---Defines the reference frame for constraint actuator values (forces/torques/velocities).
---@enum Enums.ActuatorRelativeTo 
Enums.ActuatorRelativeTo = {
	Attachment0 = 0,
	Attachment1 = 1,
	World = 2,
}

---约束驱动类型
---@enum Enums.ActuatorType 
Enums.ActuatorType = {
	None = 0,  ---无驱动，自由运动
	Motor = 1,  ---恒速旋转模式
	Servo = 2,  ---目标角度跟踪模式
}

---动画过滤器类型
---@enum Enums.AnimationFilterType 
Enums.AnimationFilterType = {
	Head = 2,  ---头
	Trunk = 4,  ---躯干
	LeftArm = 8,  ---左手臂
	RightArm = 16,  ---右手臂
	UpperBody = 30,  ---上半身（头+躯干+双臂）
	LeftLeg = 32,  ---左腿
	RightLeg = 64,  ---右腿
	LowerBody = 96,  ---下半身（双腿）
	FullBody = 126,  ---全身
}

---动画优先级。Eggy 的默认角色动画，播放时优先级为 Core。Idle 到 Action4 的优先级供开发者使用
---@enum Enums.AnimationPriority 
Enums.AnimationPriority = {
	Idle = 0,  ---推荐用于角色休闲动画的优先级
	Movement = 1,  ---推荐用于走路、跑步、游泳、攀爬和其他运动动画的优先级
	Action = 2,  ---推荐用于必须覆盖休闲和运动动画的角色动作的优先级
	Action2 = 3,  ---Action2 将覆盖 Action
	Action3 = 4,  ---Action3 将覆盖 Action2
	Action4 = 5,  ---Action4 是可用的最高优先级，覆盖所有其他优先级值
	Core = 1000,  ---最低优先级，供 Eggy 默认动画使用
}

---资产权限等级
---@enum Enums.AssetPermission 
Enums.AssetPermission = {
	None = 0,  ---权限不可用
	NoAccess = 1,  ---无权访问
	UseView = 2,  ---可使用和查看
	Edit = 3,  ---可编辑和发布
	Own = 4,  ---完全控制
}

---AxisType
---@enum Enums.AxisType 
Enums.AxisType = {
	RIGHT = 0,  ---右
	UP = 1,  ---上
	FORWARD = 2,  ---前
}

---NavMesh 烘焙模式枚举。Auto：启用 NavMesh 动态更新模式下，静态和动力学物体会参与烘焙；否则只有静态物体参与烘焙。Force：强制参与烘焙。Ignore：不参与烘焙，视为物体不存在。Disable：禁用，物体在 NavMesh 上生成不可走区域，并且上表面不生成 Mesh。
---@enum Enums.BakeMode 
Enums.BakeMode = {
	Auto = 0,  ---自动
	Force = 1,  ---强制
	Ignore = 2,  ---忽略
	Disable = 3,  ---禁用
}

---刚体类型
---@enum Enums.BodyType 
Enums.BodyType = {
	None = 0,  ---等价于 c++
	Static = 1,
	Kinematic = 2,
	Dynamic = 4,
}

---CameraMode 相机行为模式
---@enum Enums.CameraMode 
Enums.CameraMode = {
	NONE = 0,  ---不做任何处理, 常用于定点相机
	EGGY = 1,  ---蛋仔跟随模式
	SCRIPTABLE = 2,  ---脚本自定义更新行为
	FOLLOW = 3,  ---与目标保持一定关系跟随目标, 常用于玩家相机
	BIND = 4,  ---绑定在目标上, 常用于模型相机
	SCREEN_ZONE = 5,  ---参考屏幕关系跟随目标, 常用于横板游戏
	ORBIT = 6,  ---环绕跟随, 常用于静态展示
}

---相机投影方式
---@enum Enums.CameraProjection 
Enums.CameraProjection = {
	PERSPECTIVE = 0,  ---透视投影, 适用于3D场景
	ORTHOGRAPHIC = 1,  ---正交投影, 适用于2D场景
}

---相机震动曲线
---@enum Enums.CameraShakeCurve 
Enums.CameraShakeCurve = {
	SINE = 9998,  ---正弦
	NOISE = 9999,  ---随机噪声
}

---相机震动类型
---@enum Enums.CameraShakeType 
Enums.CameraShakeType = {
	FRONT_AND_BACK = 1,  ---前后
	UP_AND_DOWN = 2,  ---上下
	ROTATE = 4,  ---旋转
}

---CameraType 相机类型
---@enum Enums.CameraType 
Enums.CameraType = {
	Fixed = 0,  ---固定位置相机
	Attach = 1,  ---绑定到目标
	Watch = 2,  ---注视目标
	Track = 3,  ---追踪目标
	Follow = 4,  ---跟随目标
	Custom = 5,  ---自定义模式
	Scriptable = 6,  ---脚本控制
	Orbital = 7,  ---环绕模式
}

---阵营关系
---@enum Enums.CampRelationType 
Enums.CampRelationType = {
	SELF = 0,  ---自身
	ENEMY = 1,  ---敌对
	FRIEND = 2,  ---友好
	NEUTRAL = 4,  ---中立
	ALL_EXCEPT_SELF = 6,  ---除自己外的所有阵营
	ALL = 7,  ---所有阵营
}

---聊天显示样式
---@enum Enums.ChatStyle 
Enums.ChatStyle = {
	ClassicAndBubble = 0,  ---经典聊天 + 头顶气泡
	Classic = 1,  ---仅经典聊天
	Bubble = 2,  ---仅头顶气泡
}

---色彩分级滤镜
---@enum Enums.ColorGradingFilter 
Enums.ColorGradingFilter = {
	None = 0,  ---无滤镜效果
	SilentBlack = 1,  ---寂静黑
	PureGray = 2,  ---纯净灰
	RetroYellow = 3,  ---复古黄
	ComicBlackAndWhite = 4,  ---黑白漫画
	Woodcut = 5,  ---黑白版画
	Posterize = 6,  ---大色块
	MyriadBlooms = 7,  ---百花争艳
	Vintage = 8,  ---古色古香
	WarmSunshine = 9,  ---融融暖阳
	Sepia = 10,  ---泛黄回忆
	AutumnForest = 11,  ---层林尽染
	LotusBlush = 12,  ---芙蓉如面
	PowderRouge = 13,  ---粉黛胭脂
	CoolSummer = 14,  ---清凉夏日
	FrigidNorthland = 15,  ---凌冽北国
	NightVision = 16,  ---夜视仪
	MonoNegative = 17,  ---黑白底片
	GreenNegative = 18,  ---绿色底片
	RedNegative = 19,  ---红色底片
	MonoRed = 20,  ---单色-红
	MonoGreen = 21,  ---单色-绿
	MonoBlue = 22,  ---单色-蓝
	MonoYellow = 23,  ---单色-黄
}

---物理约束类型
---@enum Enums.ConstraintType 
Enums.ConstraintType = {
	Spring = 1,
	Hinge = 2,
	BallAndSocket = 3,
	Fixed = 4,
	Slider = 5,
	D6 = 6,
	Weld = 7,
	Rod = 8,
}

---ConsumptionMode
---@enum Enums.ConsumptionMode 
Enums.ConsumptionMode = {
	PERMANENT = 0,  ---消费模式：永久
	AMOUNT = 1,  ---消费模式：数量
	TIME = 2,  ---消费模式：时间
}

---生物角色控制器的状态类型
---@enum Enums.ControllerStateType 
Enums.ControllerStateType = {
	Climbing = "Climbing",  ---攀爬
	Dead = "Dead",  ---死亡
	EggyLiftStart = "EggyLiftStart",  ---蛋仔开始抓举
	EggyLiftThrow = "EggyLiftThrow",  ---蛋仔开始扔掉抓举单位
	EggyLifted = "EggyLifted",  ---蛋仔被抓举
	EggyRoll = "EggyRoll",  ---蛋仔滚动
	EggyRush = "EggyRush",  ---蛋仔前仆
	HumanCrouchIdle = "HumanCrouchIdle",  ---人形蹲下静止状态
	HumanCrouchMove = "HumanCrouchMove",  ---人形蹲下移动状态
	HumanRun = "HumanRun",  ---人形生物跑步
	Idle = "Idle",  ---待机
	Jumping = "Jumping",  ---跳跃
	LostControl = "LostControl",  ---失控
	Moving = "Moving",  ---移动
	PlatformStanding = "PlatformStanding",  ---PlatformStand 状态：自主移动禁用、外力可推、跳跃不退出
	ResumeControl = "ResumeControl",  ---恢复控制
	Seated = "Seated",  ---乘坐
	Swimming = "Swimming",  ---游泳
}

---CoreGui 类型枚举，对齐 CoreGuiType，并扩展 Eggy 原生控件
---@enum Enums.CoreGuiType 
Enums.CoreGuiType = {
	All = 0,  ---所有CoreGui元素
	Joystick = 1,  ---摇杆控件
	JumpButton = 2,  ---跳跃按钮
	RollButton = 3,  ---滚动按钮
	RushButton = 4,  ---前扑按钮
	LiftButton = 5,  ---举起按钮
	BattleButton = 6,  ---决战技按钮
	ResetButton = 7,  ---复位按钮
	CommunicateButton = 8,  ---沟通按钮
	EmojiButton = 9,  ---表情按钮
	PlayerList = 100,  ---玩家列表
	Health = 101,  ---血条和生命值显示
	Backpack = 102,  ---背包界面
	Chat = 103,  ---聊天界面
	TopbarContainer = 104,  ---右上角设置按钮
	EscapeMenu = 105,  ---Escape菜单
	ControlBar = 106,  ---底部控制条（移动端）
	EmotesMenu = 107,  ---情感表达界面
}

---游戏内置货币类型
---@enum Enums.CurrencyType 
Enums.CurrencyType = {
	GALLERY = 0,  ---乐园币
	GOLD = 1,  ---金豆子
}

---数据存储错误码
---@enum Enums.DataStoreErrorCode 
Enums.DataStoreErrorCode = {
	Success = 0,  ---成功
	NamespaceEmpty = 101,  ---命名空间为空
	NamespaceTooLong = 102,  ---命名空间超过50个字符
	NamespaceCharsInvalid = 103,  ---命名空间只能包含字母、数字和下划线
	DataStoreNameEmpty = 104,  ---数据存储集合名称为空
	DataStoreNameTooLong = 105,  ---数据存储集合名称超过50个字符
	DataStoreNameCharsInvalid = 106,  ---数据存储集合名称只能包含字母、数字和下划线
	ScopeEmpty = 107,  ---范围名称为空
	ScopeTooLong = 108,  ---范围名称超过50个字符
	ScopeCharsInvalid = 109,  ---范围名称只能包含字母、数字和下划线
	KeyEmpty = 110,  ---键名不能为空
	KeyTooLong = 111,  ---键名超过50个字符
	KeyCharsInvalid = 112,  ---键名只能包含字母、数字和下划线
	KeyFormatInvalidWithScope = 113,  ---AllScope模式下键名必须是scope/key格式
	ValueNotAllowed = 121,  ---不合法的值数据, 无法完成json序列化
	CantStoreValue = 122,  ---无法存储该值
	ValueTooLarge = 123,  ---值数据序列化后超过限制
	MaxValueInvalid = 131,  ---MaxValue 必须是整数
	MinValueInvalid = 132,  ---MinValue 必须是整数
	PageSizeGreater = 133,  ---PageSize 超过上限, 必须在1-100内
	PageSizeLesser = 134,  ---PageSize 低于下限, 必须在1-100内
	MinMaxOrderInvalid = 135,  ---MinValue 必须小于 MaxValue
	MetaKeyEmpty = 141,  ---元数据键名不能为空
	MetaKeyInvalid = 142,  ---元数据键名只能是字符串
	MetaKeyLengthInvalid = 143,  ---元数据键名长度必须在1-50之间
	MetaValueInvalid = 144,  ---元数据键值长度必须在0-250之间
	MetaFormatInvalid = 145,  ---元数据格式错误, 必须是字典类型
	MetaDataTooLarge = 146,  ---元数据总数据量超过限制
	UserIdsSizeLimit = 151,  ---用户ID字节长度超限
	UserIdsCountLimit = 152,  ---用户ID数量超限
	UserIdsInvalid = 153,  ---用户ID格式错误, 必须是字符串
	PrefixTooLong = 161,  ---前缀长度超过100个字符
	PrefixInvalid = 162,  ---前缀格式错误, 必须是字符串
	CursorTooLong = 163,  ---游标长度超过100个字符
	CursorInvalid = 164,  ---游标格式错误, 必须是字符串
	MinValueInvalid2 = 165,  ---minValue 如果指定必须是整数或浮点数
	MaxValueInvalid2 = 166,  ---maxValue 如果指定必须是整数或浮点数
	MinValueGreater = 167,  ---minValue 必须小于 maxValue
	IncrementAmountInvalid = 171,  ---增量值必须是整数或浮点数
	ReadThrottle = 301,  ---读取请求被丢弃, 单局游玩内吞吐量队列已满
	WriteThrottle = 302,  ---写入请求被丢弃, 单局游玩内吞吐量队列已满
	ListThrottle = 303,  ---列出请求被丢弃, 单局游玩内吞吐量队列已满
	RemoveThrottle = 304,  ---删除请求被丢弃, 单局游玩内吞吐量队列已满
	KeyReadThrottle = 305,  ---读取请求被丢弃, 存储服务侧单键名读取流量超限
	KeyWriteThrottle = 306,  ---写入请求被丢弃, 存储服务侧单键名写入流量超限
	NormalReadSpaceThrottle = 311,  ---读取请求被丢弃, 普通存储服务单服务器读速率超限制
	NormalWriteSpaceThrottle = 312,  ---写入请求被丢弃, 普通存储服务单服务器写速率超限制
	NormalListSpaceThrottle = 313,  ---列出请求被丢弃, 普通存储服务单服务器读速率超限制
	NormalRemoveSpaceThrottle = 314,  ---删除请求被丢弃, 普通存储服务单服务器写速率超限制
	OrderedReadSpaceThrottle = 321,  ---读取请求被丢弃, 有序存储服务单服务器读速率超限制
	OrderedWriteSpaceThrottle = 322,  ---写入请求被丢弃, 有序存储服务单服务器写速率超限制
	OrderedListSpaceThrottle = 323,  ---列出请求被丢弃, 有序存储服务单服务器读速率超限制
	OrderedRemoveSpaceThrottle = 324,  ---删除请求被丢弃, 有序存储服务单服务器写速率超限制
	NormalReadTotalThrottle = 331,  ---读取请求被丢弃, 普通存储服务所有服务器读速率超限制
	NormalWriteTotalThrottle = 332,  ---写入请求被丢弃, 普通存储服务所有服务器写速率超限制
	NormalListTotalThrottle = 333,  ---列出请求被丢弃, 普通存储服务所有服务器列出速率超限制
	NormalRemoveTotalThrottle = 334,  ---删除请求被丢弃, 普通存储服务所有服务器删除速率超限制
	OrderedReadTotalThrottle = 341,  ---读取请求被丢弃, 有序存储服务所有服务器读速率超限制
	OrderedWriteTotalThrottle = 342,  ---写入请求被丢弃, 有序存储服务所有服务器写速率超限制
	OrderedListTotalThrottle = 343,  ---列出请求被丢弃, 有序存储服务所有服务器列出速率超限制
	OrderedRemoveTotalThrottle = 344,  ---删除请求被丢弃, 有序存储服务所有服务器删除速率超限制
	DataStoreNotExist = 401,  ---数据存储集合不存在
	DataStoreDeleted = 402,  ---数据存储集合已删除
	OrderedDataStoreNotExist = 403,  ---有序数据存储集合不存在
	OrderedDataStoreDeleted = 404,  ---有序数据存储集合已删除
	OrderedDataStoreValueMustBeInt = 411,  ---有序数据存储集合的值必须是整数
	DataStoreServiceNotReady = 412,  ---数据存储服务未准备好, 无法完成操作
	DataStoreServiceError = 413,  ---数据存储服务内部错误, 无法完成操作
	DataStoreServiceNotReach = 414,  ---数据存储服务未就绪, 无法完成操作
	OperationNotSupported = 415,  ---不支持此操作 (例如 Ordered 类型调 Version API)
	KeyNotFound = 501,  ---键名不存在
	KeyRemoved = 502,  ---键名已删除
	DocInvalid = 503,  ---文档格式错误
	VersionMismatch = 504,  ---版本不匹配, 期望版本与实际版本不一致
	VersionInvalid = 505,  ---非法的版本
	VersionNotFound = 506,  ---版本已过期或不存在
}

---数据存储类型
---@enum Enums.DataStoreType 
Enums.DataStoreType = {
	Normal = 1,  ---普通数据存储
	Ordered = 2,  ---有序数据存储
	Global = 3,  ---全局数据存储
}

---DefaultCameraPresetType
---@enum Enums.DefaultCameraPresetType 
Enums.DefaultCameraPresetType = {
	VOID = 0,  ---不做变更
	FIRST_PERSON = 1,  ---第一人称
	THIRD_PERSON = 2,  ---第三人称
	SIDE_SCROLLING = 3,  ---横板游戏
	STATIC_MODEL = 4,  ---模型展示
}

---DevCameraOcclusionMode 相机遮挡处理模式
---@enum Enums.DevCameraOcclusionMode 
Enums.DevCameraOcclusionMode = {
	Zoom = 0,  ---被遮挡时拉近相机，保持清晰视野
	Invisicam = 1,  ---遮挡时使目标半透明（简化版）
	EggyHybrid = 2,  ---推镜头 + 目标半透明（蛋仔独有，同时支持两种效果）
}

---移动端移动类型
---@enum Enums.DevTouchMovementMode 
Enums.DevTouchMovementMode = {
	UserChoice = 0,  ---玩家选择
	Thumbstick = 1,  ---随指摇杆
	FixedThumbstick = 2,  ---固定摇杆
	DynamicThumbstick = 3,  ---动态摇杆
	Scriptable = 4,  ---隐藏摇杆，脚本接管移动
}

---生物头顶名字与血条的显示距离判定方式，用于决定隐藏、按观察者距离显示或按被观察者距离显示。
---@enum Enums.DisplayDistanceType 
Enums.DisplayDistanceType = {
	None = 0,  ---隐藏
	Viewer = 1,  ---观察者距离
	Subject = 2,  ---被观察者距离
}

---EUIAdaptMode
---@enum Enums.EUIAdaptMode 
Enums.EUIAdaptMode = {
	None = 0,  ---无对齐
	Absolute = 1,  ---像素对齐
	Percent = 2,  ---百分比对齐
}

---EUIAnchorAdaptMode
---@enum Enums.EUIAnchorAdaptMode 
Enums.EUIAnchorAdaptMode = {
	None = 0,  ---经典对齐
	Percent = 1,  ---百分比对齐
}

---EUIArrangeMode
---@enum Enums.EUIArrangeMode 
Enums.EUIArrangeMode = {
	SingleLine = 1,  ---单行排列
	AutoWrap = 2,  ---自动换行
}

---EUIFillDirection
---@enum Enums.EUIFillDirection 
Enums.EUIFillDirection = {
	Horizontal = 0,  ---水平
	Vertical = 1,  ---垂直
}

---EUIGridStartCorner
---@enum Enums.EUIGridStartCorner 
Enums.EUIGridStartCorner = {
	TopLeft = 0,  ---左上
	TopRight = 1,  ---右上
	BottomLeft = 2,  ---左下
	BottomRight = 3,  ---右下
}

---EUIHorizontalAlignment
---@enum Enums.EUIHorizontalAlignment 
Enums.EUIHorizontalAlignment = {
	Left = 0,  ---左对齐
	Center = 1,  ---居中对齐
	Right = 2,  ---右对齐
}

---EUIListviewGravity
---@enum Enums.EUIListviewGravity 
Enums.EUIListviewGravity = {
	Left = 0,  ---左对齐
	Right = 1,  ---右对齐
	HorizontalCenter = 2,  ---水平居中
	Top = 3,  ---上对齐
	Bottom = 4,  ---下对齐
	VerticalCenter = 5,  ---垂直居中
}

---EUIOverflowPolicy
---@enum Enums.EUIOverflowPolicy 
Enums.EUIOverflowPolicy = {
	Culling = 1,  ---移除剔除
	Ellipsis = 2,  ---溢出省略
	AutoScroll = 3,  ---溢出跑马灯
}

---EUIOverflowStrategy
---@enum Enums.EUIOverflowStrategy 
Enums.EUIOverflowStrategy = {
	None = 0,  ---截断
	AutoWrap = 1,  ---强制换行
	Ellipsis = 2,  ---省略号
	AutoScroll = 3,  ---走马灯
	HorizontalScroll = 4,  ---横向走马灯
}

---EUIProgressDirection
---@enum Enums.EUIProgressDirection 
Enums.EUIProgressDirection = {
	Normal = 0,  ---正向
	Reverse = 1,  ---反向
}

---EUIResetSizePolicy
---@enum Enums.EUIResetSizePolicy 
Enums.EUIResetSizePolicy = {
	AutoScroll = 0,  ---自动滚动
	FitWidth = 1,  ---按宽自适应
	FitHeight = 2,  ---按高自适应
}

---EUIScrollDirection
---@enum Enums.EUIScrollDirection 
Enums.EUIScrollDirection = {
	Vertical = 1,  ---垂直
	Horizontal = 2,  ---水平
}

---EUISortOrderType
---@enum Enums.EUISortOrderType 
Enums.EUISortOrderType = {
	LayoutOrder = 0,  ---按布局顺序
	Name = 1,  ---按名称
}

---EUITableMajorAxis
---@enum Enums.EUITableMajorAxis 
Enums.EUITableMajorAxis = {
	RowMajor = 0,  ---行主序
	ColumnMajor = 1,  ---列主序
}

---EUITextHorizontalAlignment
---@enum Enums.EUITextHorizontalAlignment 
Enums.EUITextHorizontalAlignment = {
	Left = 0,  ---左对齐
	Center = 1,  ---居中对齐
	Right = 2,  ---右对齐
}

---EUITextVerticalAlignment
---@enum Enums.EUITextVerticalAlignment 
Enums.EUITextVerticalAlignment = {
	Top = 0,  ---顶部对齐
	Center = 1,  ---居中对齐
	Bottom = 2,  ---底部对齐
}

---EUIVerticalAlignment
---@enum Enums.EUIVerticalAlignment 
Enums.EUIVerticalAlignment = {
	Top = 0,  ---顶部对齐
	Center = 1,  ---居中对齐
	Bottom = 2,  ---底部对齐
}

---EasingDirection 缓动方向枚举
---@enum Enums.EasingDirection 
Enums.EasingDirection = {
	In = 0,  ---正向缓动
	Out = 1,  ---反向缓动
	InOut = 2,  ---先 In 后 Out
	OutIn = 3,  ---先 Out 后 In
}

---EasingStyle 缓动曲线枚举
---@enum Enums.EasingStyle 
Enums.EasingStyle = {
	Linear = 0,  ---线性
	Quad = 1,  ---二次曲线
	Cubic = 2,  ---三次曲线
	Quart = 3,  ---四次曲线
	Quint = 4,  ---五次曲线
	Sine = 5,  ---正弦曲线
	Back = 6,  ---回弹效果
	Bounce = 7,  ---弹跳效果
	Elastic = 8,  ---弹性效果
	Exponential = 9,  ---指数曲线
	Circular = 10,  ---圆弧曲线
}

---特效绑定类型
---@enum Enums.EffectBindType 
Enums.EffectBindType = {
	POS = 1,  ---仅位置
	POS_ROT = 3,  ---位置+旋转
	POS_SCALE = 5,  ---位置+缩放
	ALL = 7,  ---全部跟随
}

---蛋仔的动态表情状态，覆盖待机、开心、伤心、生气、思考、震惊、害怕、大笑、说话等常见情绪与动作表情。
---@enum Enums.FaceStatus 
Enums.FaceStatus = {
	Afraid = "afraid",  ---害怕
	Angry = "angry",  ---生气
	Bad = "bad",  ---阴险
	Confuse = "confuse",  ---疑惑
	Disgusted = "disgusted",  ---厌恶
	Expect = "expect",  ---期待
	Happy = "happy",  ---开心
	Idle = "idle",  ---待机
	Jump = "jump",  ---跳跃
	Laugh = "laugh",  ---大笑
	Sad = "sad",  ---伤心
	Shock = "shock",  ---震惊
	Speak = "speak",  ---说话
	SpecialIdle = "special_idle",  ---专属待机
	Struggle = "struggle",  ---飞扑
	Think = "think",  ---思考
}

---蛋仔散件时装的部位类型，分为头部、上半身和下半身，用于按部位进行换装或重置。
---@enum Enums.FashionPartType 
Enums.FashionPartType = {
	Head = 1,
	Body = 2,
	Leg = 3,
}

---视场角模式
---@enum Enums.FieldOfViewMode 
Enums.FieldOfViewMode = {
	Vertical = 0,
	Diagonal = 1,
	MaxAxis = 2,
}

---渐变天空渐变轴向
---@enum Enums.GradientSkyDirection 
Enums.GradientSkyDirection = {
	X = 0,  ---X 轴
	Y = 1,  ---Y 轴
}

---HorizontalAlignmentType
---@enum Enums.HorizontalAlignmentType 
Enums.HorizontalAlignmentType = {
	ALIGN_LEFT = 0,  ---左对齐
	ALIGN_CENTER = 1,  ---居中对齐
	ALIGN_RIGHT = 2,  ---右对齐
}

---生物头顶血条的显示模式，可选择不显示、常驻显示，或仅在生命值不满时显示。
---@enum Enums.HpBarShowMode 
Enums.HpBarShowMode = {
	None = 0,  ---不显示
	Persistent = 1,  ---常驻显示
	NotFull = 2,  ---血量不满时显示
}

---染色区域Key
---@enum Enums.HumanMeshColor 
Enums.HumanMeshColor = {
	COLOR1 = "paint_area1",  ---区域1
	COLOR2 = "paint_area2",  ---区域2
	COLOR3 = "paint_area3",  ---区域3
	COLOR4 = "paint_area4",  ---区域4
}

---KeyCode
---@enum Enums.KeyCode 
Enums.KeyCode = {
	MouseLeft = 1,  ---Mouse Buttons
	MouseRight = 2,
	MouseMiddle = 4,
	Backspace = 8,  ---Standard Keys
	Tab = 9,
	Return = 13,
	Shift = 16,  ---通用 Shift
	Ctrl = 17,  ---通用 Ctrl
	Alt = 18,  ---通用 Alt
	CapsLock = 20,
	Escape = 27,
	Space = 32,
	PageUp = 33,  ---Navigation & Editing
	PageDown = 34,
	End = 35,
	Home = 36,
	Left = 37,
	Up = 38,
	Right = 39,
	Down = 40,
	Print = 44,  ---VK_SNAPSHOT
	Insert = 45,
	Delete = 46,
	Zero = 48,  ---Digits (0-9)
	One = 49,
	Two = 50,
	Three = 51,
	Four = 52,
	Five = 53,
	Six = 54,
	Seven = 55,
	Eight = 56,
	Nine = 57,
	A = 65,  ---Letters (A-Z)
	B = 66,
	C = 67,
	D = 68,
	E = 69,
	F = 70,
	G = 71,
	H = 72,
	I = 73,
	J = 74,
	K = 75,
	L = 76,
	M = 77,
	N = 78,
	O = 79,
	P = 80,
	Q = 81,
	R = 82,
	S = 83,
	T = 84,
	U = 85,
	V = 86,
	W = 87,
	X = 88,
	Y = 89,
	Z = 90,
	KeypadZero = 96,
	KeypadOne = 97,
	KeypadTwo = 98,
	KeypadThree = 99,
	KeypadFour = 100,
	KeypadFive = 101,
	KeypadSix = 102,
	KeypadSeven = 103,
	KeypadEight = 104,
	KeypadNine = 105,
	KeypadMultiply = 106,  ---VK_NUMMUL
	KeypadPlus = 107,  ---VK_NUMADD
	KeypadMinus = 109,  ---VK_NUMDEC
	KeypadPeriod = 110,  ---VK_NUMDOT
	KeypadDivide = 111,  ---VK_NUMDIV
	F1 = 112,  ---Function Keys
	F2 = 113,
	F3 = 114,
	F4 = 115,
	F5 = 116,
	F6 = 117,
	F7 = 118,
	F8 = 119,
	F9 = 120,
	F10 = 121,
	F11 = 122,
	F12 = 123,
	NumLock = 144,  ---Keypad
	LeftShift = 160,
	RightShift = 161,
	LeftControl = 162,
	RightControl = 163,
	LeftAlt = 164,
	RightAlt = 165,
	Equals = 187,  ---VK_ADD (Main keyboard +/=)
	Minus = 189,  ---VK_DEC (Main keyboard -/_)
}

---内存存储错误码枚举。
---@enum Enums.MemoryStoreErrorCode 
Enums.MemoryStoreErrorCode = {
	Success = 0,  ---成功
	LocalInternalError = 101,  ---本地内部错误
	UnpublishedPlace = 102,  ---未发布的作品不能使用 MemoryStoreService
	InvalidClientAccess = 103,  ---MemoryStoreService 必须从服务器调用
	InvalidExpirationTime = 104,  ---过期时间必须在当前时间之后
	LocalInvalidRequest = 105,  ---请求参数错误，无法序列化
	InvalidSortKey = 106,  ---排序键必须是数字或字符串
	TransformCallbackFailed = 107,  ---调用转换回调函数失败
	RequestThrottled = 108,  ---请求被限流
	UpdateRetryTimesLimit = 109,  ---更新冲突后，超过最大重试次数
	LocalErrorEnd = 999,  ---本地错误码结束
	AccessDenied = 1001,  ---未授权访问数据
	InternalError = 1003,  ---远端服务内部错误
	InvalidRequest = 1004,  ---请求参数错误
	ServiceNotReady = 1005,  ---服务未就绪
	StoreMemoryOverLimit = 1101,  ---超过数据结构级别内存大小限制 (100MB)
	StoreItemsOverLimit = 1102,  ---超过数据结构元素个数限制 (1M)
	KeyValueSizeTooLarge = 1103,  ---单个键值大小超过限制 (1MB)
	KeySizeTooLarge = 1104,  ---单个键大小超过限制 (128B)
	SortKeySizeTooLarge = 1105,  ---单个排序键大小超过限制 (128B)
	StoreRequestsOverLimit = 1200,  ---超过单个数据结构级别请求次数限制
	TotalRequestsOverLimit = 1201,  ---超过总请求次数限制
	PartitionRequestsOverLimit = 1202,  ---超过分区请求次数限制
	TotalMemoryOverLimit = 1203,  ---超过总内存限制
	DataUpdateConflict = 1301,  ---数据更新冲突
	NoItemFound = 1302,  ---未找到指定元素 (Queue:ReadAsync 空队列)
	KeyExists = 1303,  ---键已存在 (NX 条件失败)
	KeyNotExists = 1304,  ---键不存在 (XX 条件失败)
	MemoryStoreExists = 1305,  ---数据结构已存在 (MSNX 条件失败)
	MemoryStoreNotExists = 1306,  ---数据结构不存在 (MSXX 条件失败)
	VauleIsNotNumber = 1307,  ---键值不是数字 (INCR 条件失败)；原文保留拼写 Vaule
	RequestValueIsNotNumber = 1308,  ---请求更新键值不是数字 (INCR 条件失败)
	DataUpdateConditionDissatisfy = 1309,  ---数据更新条件不满足 (GT/LT/LTE/GTE/LTT/LTET/GTT/GTET/EQT/NEQT)
	DataUpdateVersionDissatisfy = 1310,  ---数据更新版本不满足 (UpdateAsync CAS 版本冲突；DependPrevVersion 与当前版本不一致)
}

---日志消息类型枚举
---@enum Enums.MessageType 
Enums.MessageType = {
	MessageOutput = 0,
	MessageInfo = 1,
	MessageWarning = 2,
	MessageError = 3,
}

---MouseBehavior 鼠标行为枚举
---@enum Enums.MouseBehavior 
Enums.MouseBehavior = {
	Default = 0,  ---默认：光标可自由移动，不锁定
	LockCenter = 1,  ---锁定到屏幕中心：隐藏光标并锁中心，鼠标移动以相对位移形式上报（第一人称相机范式）
	LockCurrentPosition = 2,  ---锁定到当前位置：光标固定在当前屏幕坐标
}

---物理 Owner 变更方式
---@enum Enums.NetworkOwnerChangeType 
Enums.NetworkOwnerChangeType = {
	Automatically = 1,
	Manually = 2,
}

---路径计算状态
---@enum Enums.PathStatus 
Enums.PathStatus = {
	Success = 0,  ---路径计算成功
	NoPath = 5,  ---无法找到路径
}

---路点到达动作
---@enum Enums.PathWaypointAction 
Enums.PathWaypointAction = {
	Walk = 0,  ---普通地面移动
	Jump = 1,  ---跳跃（off-mesh link）
	Custom = 2,  ---自定义动作（预留）
}

---PlayerPlatformSpenderStatus 玩家跨平台消费状态枚举
---@enum Enums.PlayerPlatformSpenderStatus 
Enums.PlayerPlatformSpenderStatus = {
	Unknown = 0,  ---数据不可用
	Active = 1,  ---活跃的跨平台消费者
	OtherPayer = 2,  ---非活跃消费者（包括完全未消费）
}

---预设链接状态
---@enum Enums.PresetLinkStatus 
Enums.PresetLinkStatus = {
	UpToDate = 0,  ---已是最新版本
	Changed = 1,  ---本地有修改
	NewVersionAvailable = 2,  ---有新版本可用
	ChangedAndNewVersion = 3,  ---本地修改且有新版本
}

---固定天空模板
---@enum Enums.PresetSkyTemplate 
Enums.PresetSkyTemplate = {
	DreamGalaxy = 19,  ---幽梦星河
	MorningStarRhythm = 20,  ---启明律动
	FairyMusicLand = 23,  ---仙灵音境
	SweetDreamPlanet = 36,  ---美梦星球
	NightmarePlanet = 37,  ---噩梦星球
	AuroraBorealis = 56,  ---北极之光
	DeepSeaCoralReef = 74,  ---深海珊瑚礁
	CosmicSphere = 81,  ---圆宇宙星体
	Museum = 100,  ---博物馆
	MistGlow = 142,  ---烟光凝
}

---用于 RaycastParams/OverlapParams 对象中，决定 FilterDescendantsInstances 列表的使用方式：Exclude(0) 跳过列表中的 Unit；Include(1) 仅返回列表中的 Unit。
---@enum Enums.RaycastFilterType 
Enums.RaycastFilterType = {
	Exclude = 0,  ---排除列表
	Include = 1,  ---仅包含列表
}

---生物身体上的骨骼挂点位置，用于在指定部位绑定外观件、特效或道具。
---@enum Enums.SkeletalSocketType 
Enums.SkeletalSocketType = {
	Spine = "socket_body",  ---身体
	LFoot = "socket_foot_l",  ---左脚
	RFoot = "socket_foot_r",  ---右脚
	LForearm = "socket_forearm_l",  ---左臂
	RForearm = "socket_forearm_r",  ---右臂
	LHand = "socket_hand_l",  ---左手
	RHand = "socket_hand_r",  ---右手
	Head = "socket_head",  ---头部
	Origin = "socket_origin",  ---底面中心
	LWeapon = "socket_weapon_l",  ---左手武器
	RWeapon = "socket_weapon_r",  ---右手武器
}

---天空模板
---@enum Enums.SkyTemplate 
Enums.SkyTemplate = {
	Night = 1,  ---夜晚
	Dusk = 2,  ---黄昏
	Day = 4,  ---白天
	AmusementPark = 6,  ---游乐园
	Circus = 7,  ---马戏团
	SeaIsland = 8,  ---海岛
	MagpieBridge = 11,  ---鹊桥相会
	SunMoonStars = 12,  ---日月星辰
	SportsFieldDay = 13,  ---运动场-白天
	MoonAboveClouds = 14,  ---云上圆月
	SportsFieldNight = 15,  ---运动场-夜晚
	CandyValley = 16,  ---糖果河谷
	SpookyCastle = 17,  ---惊悚古堡
	CakeRoundTable = 18,  ---蛋糕圆桌
	ColorfulSpace = 21,  ---幻彩空间
	DragonEggIsland = 24,  ---龙蛋岛
	LavaRealm = 25,  ---熔岩领域
	ChineseGarden = 27,  ---园林
	Moon = 28,  ---月球上空
	Earth = 29,  ---地球上空
	OuterSpace = 30,  ---太空
	Desert = 33,  ---沙漠
	SichuanTrendDay = 38,  ---蜀中国潮-白天
	SichuanTrendDusk = 39,  ---蜀中国潮-黄昏
	SichuanTrendNight = 40,  ---蜀中国潮-晚上
	ZeroGravityParty1 = 41,  ---失重派对-一
	ZeroGravityParty2 = 42,  ---失重派对-二
	ZeroGravityParty3 = 43,  ---失重派对-三
	MorningForest = 45,  ---清晨森林
	PhantomForest = 50,  ---魅影森林
	ChineseStyleCloudSea = 51,  ---国风云海
	ChineseStyleMountainRiver = 52,  ---国风山川
	FlowerField = 53,  ---花丛
	HorrorFog = 54,  ---恐怖迷雾
	PinkSnowfield = 55,  ---粉色雪原
	Forest = 57,  ---森林
	Underwater = 58,  ---海底
	City = 59,  ---都市
	CozyCottageDay = 62,  ---温馨小屋-白天
	CozyCottageNight = 63,  ---温馨小屋-晚上
	WindingRainbowRoad = 66,  ---蜿蜒彩道
	SharkIsland = 67,  ---鲨鱼海岛
	Clear = 69,  ---晴朗天空
	ClearNight = 75,  ---清朗夜空
	Dusk2 = 76,  ---黄昏天空
	TwilightForest = 78,  ---暮夜森林
	Desert2 = 85,  ---沙漠
	Classroom = 95,  ---教室
	FloatingMist = 102,  ---浮岚卷岫
}

---排序方向枚举。
---@enum Enums.SortDirection 
Enums.SortDirection = {
	Descending = -1,  ---降序 (DESC)
	Ascending = 1,  ---升序 (ASC)
}

---Space 关闭原因枚举。
---@enum Enums.SpaceCloseReason 
Enums.SpaceCloseReason = {
	Unknown = 0,  ---未知原因关闭
	OfficalMaintenance = 1,  ---蛋仔官方维护服务器
	DeveloperShutdown = 2,  ---开发者已经关闭了服务器，或者在 Studio 中调用了绑定到 BindToClose() 的函数
	DeveloperUpdate = 3,  ---开发者已将服务器迁移到新版本的地方
	ServerEmpty = 4,  ---最后一个玩家已离开
	OutOfMemory = 5,  ---Space 已达到游戏服务器的内存限制
}

---TableMajorAxis
---@enum Enums.TableMajorAxis 
Enums.TableMajorAxis = {
	RowMajor = 0,  ---直接子节点代表行，行内子节点代表单元格
	ColumnMajor = 1,  ---直接子节点代表列，列内子节点代表单元格
}

---传送错误码
---@enum Enums.TeleportErrcode 
Enums.TeleportErrcode = {
	SUCCESS = 0,  ---成功
	FAILURE = 1,  ---失败
	GAME_NOT_FOUND = 2,  ---找不到实例
	GAME_END = 3,  ---实例已经结束
	GAME_FULL = 4,  ---实例玩家已满
	UNAUTHORIZED = 5,  ---未授权的行为
	FLOODED = 6,  ---过于频繁的请求
	IS_TELEPORTING = 7,  ---已经在传送中
	NOT_IMPLEMENTED = 8,  ---未实现的行为
	TIMEOUT = 9,  ---超时
	ACCESS_DENIED = 10,  ---访问权限不匹配
}

---传送状态
---@enum Enums.TeleportState 
Enums.TeleportState = {
	RequestedFromServer = 0,  ---服务器请求客户端进行传送
	Started = 1,  ---客户端已开始尝试传送
	WaitingForServer = 2,  ---客户端正在等待服务器对传送请求的响应
	Failed = 3,  ---传送失败
	InProgress = 4,  ---传送当前正在进行中。玩家通常会断开连接并在此之后传送到目的地
	Finish = 5,  ---传送完成
}

---官方文字聊天频道的类型，包括所有玩家可见的全体频道与仅限同阵营玩家的阵营频道。
---@enum Enums.TextChatChannelType 
Enums.TextChatChannelType = {
	All = "All",  ---所有
	Camp = "Camp",  ---阵营
}

---TextFontType
---@enum Enums.TextFontType 
Enums.TextFontType = {
	FZLONGKSXSJW = "FZLongKSXSJW.ttf",  ---行书
	YUANTI_BOLD = "HuaWenYuanTi-Bold-2.ttf",  ---粗圆体
	YUANTI_REGULAR = "HuaWenYuanTi-REGULAR-2.ttf",  ---细圆体
	BIAOTISONG_W9 = "Huakangbiaotisong_w9.ttf",  ---宋体
	WEIBEI_W7 = "Huakangweibei_w7.ttf",  ---魏碑体
	SHANGSHOUZHUIGUANG = "Shangshouzhuiguang.ttf",  ---手写体
	HKXZYT_W9_GB = "hkxzyt_w9_gb.ttf",  ---综艺体
}

---TextOverflowStrategy
---@enum Enums.TextOverflowStrategy 
Enums.TextOverflowStrategy = {
	OVERFLOW_NONE = 0,  ---溢出
	OVERFLOW_CUTOFF = 1,  ---截断
	OVERFLOW_SCROLL = 2,  ---跑马
}

---头像缩略图尺寸
---@enum Enums.ThumbnailSize 
Enums.ThumbnailSize = {
	Size48x48 = 48,  ---48x48 像素
	Size50x50 = 50,  ---50x50 像素
	Size60x60 = 60,  ---60x60 像素
	Size75x75 = 75,  ---75x75 像素
	Size100x100 = 100,  ---100x100 像素
	Size150x150 = 150,  ---150x150 像素（默认）
	Size180x180 = 180,  ---180x180 像素
	Size352x352 = 352,  ---352x352 像素
	Size420x420 = 420,  ---420x420 像素
	Size720x720 = 720,  ---720x720 像素
}

---头像缩略图类型
---@enum Enums.ThumbnailType 
Enums.ThumbnailType = {
	HeadShot = 1,  ---头部特写（与 AvatarBust / AvatarThumbnail 首期行为等价）
	AvatarBust = 2,  ---半身像（与 HeadShot / AvatarThumbnail 首期行为等价）
	AvatarThumbnail = 3,  ---全身头像（与 HeadShot / AvatarBust 首期行为等价）
}

---TweenPlayState Tween 播放状态枚举
---@enum Enums.TweenPlayState 
Enums.TweenPlayState = {
	Begin = 0,  ---初始状态，尚未播放
	Delayed = 1,  ---等待延迟时间结束
	Playing = 2,  ---正在插值中
	Paused = 3,  ---已暂停
	Completed = 4,  ---已完成所有循环
	Cancelled = 5,  ---已被取消
}

---TweenStatus Tween 回调状态枚举
---@enum Enums.TweenStatus 
Enums.TweenStatus = {
	Completed = 0,  ---自然完成或 time<=0 立即完成
	Canceled = 1,  ---被 override 抢占而提前终止
}

---UserInputState 用户输入状态枚举
---@enum Enums.UserInputState 
Enums.UserInputState = {
	Begin = 0,  ---输入开始
	Change = 1,  ---输入变化
	End = 2,  ---输入结束
	Cancel = 3,  ---输入取消
	None = 4,  ---输入无状态
}

---UserInputType 用户输入类型枚举
---@enum Enums.UserInputType 
Enums.UserInputType = {
	None = 0,  ---未知输入
	MouseButton1 = 1,  ---鼠标按钮1（左键）
	MouseButton2 = 2,  ---鼠标按钮2（右键）
	MouseButton3 = 3,  ---鼠标按钮3（中键）
	MouseWheel = 4,  ---鼠标滚轮向上
	MouseMovement = 5,  ---鼠标移动
	Keyboard = 6,  ---键盘按键
	Touch = 7,  ---触摸
	Accelerometer = 8,  ---加速度计
	Gyroscope = 9,  ---陀螺仪
	Gamepad1 = 10,  ---游戏手柄1
	Gamepad2 = 11,  ---游戏手柄2
	Gamepad3 = 12,  ---游戏手柄3
	Gamepad4 = 13,  ---游戏手柄4
	TextInput = 14,  ---文本输入
	InputMethod = 15,  ---输入法
}

---VerticalAlignmentType
---@enum Enums.VerticalAlignmentType 
Enums.VerticalAlignmentType = {
	ALIGN_TOP = 0,  ---顶部对齐
	ALIGN_MIDDLE = 1,  ---中间对齐
	ALIGN_BOTTOM = 2,  ---底部对齐
}

---WhenUserFirstPlayed 玩家首次游玩时间枚举
---@enum Enums.WhenUserFirstPlayed 
Enums.WhenUserFirstPlayed = {
	Unknown = 0,  ---数据不可用
	Days0To30 = 1,  ---过去 30 天内首次游玩
	Days31To90 = 2,  ---31-90 天前首次游玩
	Days91To180 = 3,  ---91-180 天前首次游玩
	Days181To365 = 4,  ---181-365 天前首次游玩
	Days366Plus = 5,  ---365 天前首次游玩
}

--========================== 服务 Service ==========================

---广告服务
---@class AdvertisementService : Unit
local AdvertisementService = {}

---播放激励视频广告
---@param player Player 玩家对象
---@param successEvent String 成功事件
---@param failEvent String 失败事件
---@param adTag String 广告标签
---@param successData Table 成功数据
---@param failData Table 失败数据
function AdvertisementService:PlayAdvertisementWithEvent(player, successEvent, failEvent, adTag, successData, failData) end

---播放激励视频广告并发放商品奖励
---@param player Player 玩家对象
---@param goodsId String 商品ID
---@param successEvent String 成功事件
---@param failEvent String 失败事件
---@param adTag String 广告标签
function AdvertisementService:ShowRewardedVideoAd(player, goodsId, successEvent, failEvent, adTag) end

---AnalyticsService 数据分析与事件追踪服务
---**适用范围**: 仅服务端
---@class AnalyticsService : Unit
local AnalyticsService = {}

---在协程中异步查询玩家{#0}的分段数据
---**适用范围**: 仅服务端
---@param player Player 玩家对象（必须在当前 Space 内）
---@return Table 分段数据：HasData(bool)；ActivePayerStatus(Top15Percent/Intermediate35Percent/Casual50Percent/Never/Lapsed/Unknown)；WhenUserFirstPlayed(Days0To30/Days31To90/Days91To180/Days181To365/Days366Plus/Unknown)；PlayerPlatformSpenderStatus(Active/OtherPayer/Unknown)
function AnalyticsService:GetPlayerSegmentsAsync(player) end

---记录玩家{#0}的自定义事件{#1}，事件值{#2}，附加数据{#3}
---**适用范围**: 仅服务端
---@param player Player 玩家对象（事件归属，必须在当前 Space 内）
---@param eventName String 事件名称（非空，≤50 字符，仅允许 [a-zA-Z0-9_]）
---@param value number 事件值，用于 sum/avg 聚合（number，缺省 1）
---@param customData Table 自定义数据（key 仅限 CustomField01/02/03；value 支持 str/int/float/bool，str≤256 且不含 , " \r \n）
function AnalyticsService:LogCustomEvent(player, eventName, value, customData) end

---记录玩家{#0}的经济事件，流向{#1}，货币{#2}，数量{#3}，余额{#4}，交易类型{#5}，物品SKU{#6}，附加数据{#7}
---**适用范围**: 仅服务端
---@param player Player 玩家对象（事件归属，必须在当前 Space 内）
---@param flowType String 流向类型（仅 Source / Sink）
---@param currencyType String 货币类型（非空，≤50 字符，仅允许 [a-zA-Z0-9_]）
---@param amount number 变化数量（必须 >0）
---@param endingBalance number 结束余额（必须 >=0）
---@param transactionType String 交易类型（非空，≤50 字符，仅 [a-zA-Z0-9_]；推荐使用 IAP/Shop/Gameplay/ContextualPurchase/TimedReward/Onboarding）
---@param itemSku String 物品SKU（可选，≤50 字符）
---@param customData Table 自定义数据（key 仅限 CustomField01/02/03；value 支持 str/int/float/bool，str≤256 且不含 , " \r \n）
function AnalyticsService:LogEconomyEvent(player, flowType, currencyType, amount, endingBalance, transactionType, itemSku, customData) end

---记录玩家{#0}的漏斗{#1}步骤{#3}：{#4}，会话{#2}，附加数据{#5}
---**适用范围**: 仅服务端
---@param player Player 玩家对象（事件归属，必须在当前 Space 内）
---@param funnelName String 漏斗名称（非空，≤50 字符，仅允许 [a-zA-Z0-9_]）
---@param funnelSessionId String 漏斗会话ID（可选，≤50 字符）
---@param step number 步骤编号（整数 1-100）
---@param stepName String 步骤名称（可选，≤50 字符）
---@param customData Table 自定义数据（key 仅限 CustomField01/02/03；value 支持 str/int/float/bool，str≤256 且不含 , " \r \n）
function AnalyticsService:LogFunnelStepEvent(player, funnelName, funnelSessionId, step, stepName, customData) end

---记录玩家{#0}的新手引导漏斗步骤{#1}：{#2}，附加数据{#3}
---**适用范围**: 仅服务端
---@param player Player 玩家对象（事件归属，必须在当前 Space 内）
---@param step number 步骤编号（整数 1-100）
---@param stepName String 步骤名称（可选，≤50 字符）
---@param customData Table 自定义数据（key 仅限 CustomField01/02/03；value 支持 str/int/float/bool，str≤256 且不含 , " \r \n）
function AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName, customData) end

---记录玩家{#0}的进度完成事件，路径{#1}，关卡{#2}，关卡名{#3}，附加数据{#4}
---**适用范围**: 仅服务端
---@param player Player 玩家对象（事件归属，必须在当前 Space 内）
---@param progressionPathName String 进度路径名称（非空，≤50 字符，仅允许 [a-zA-Z0-9_]）
---@param level Any 关卡（number 或 string；string ≤50 字符）
---@param levelName String 关卡名称（可选，≤50 字符）
---@param customData Table 自定义数据（progression 事件允许任意 key；value 支持 str/int/float/bool，str≤256 且不含 , " \r \n）
function AnalyticsService:LogProgressionCompleteEvent(player, progressionPathName, level, levelName, customData) end

---记录玩家{#0}的进度事件，路径{#1}，状态{#2}，关卡{#3}，关卡名{#4}，附加数据{#5}
---**适用范围**: 仅服务端
---@param player Player 玩家对象（事件归属，必须在当前 Space 内）
---@param progressionPathName String 进度路径名称（非空，≤50 字符，仅允许 [a-zA-Z0-9_]）
---@param status String 状态（仅 Start / Complete / Fail）
---@param level Any 关卡（number 或 string；string ≤50 字符）
---@param levelName String 关卡名称（可选，≤50 字符）
---@param customData Table 自定义数据（progression 事件允许任意 key；value 支持 str/int/float/bool，str≤256 且不含 , " \r \n）
function AnalyticsService:LogProgressionEvent(player, progressionPathName, status, level, levelName, customData) end

---记录玩家{#0}的进度失败事件，路径{#1}，关卡{#2}，关卡名{#3}，附加数据{#4}
---**适用范围**: 仅服务端
---@param player Player 玩家对象（事件归属，必须在当前 Space 内）
---@param progressionPathName String 进度路径名称（非空，≤50 字符，仅允许 [a-zA-Z0-9_]）
---@param level Any 关卡（number 或 string；string ≤50 字符）
---@param levelName String 关卡名称（可选，≤50 字符）
---@param customData Table 自定义数据（progression 事件允许任意 key；value 支持 str/int/float/bool，str≤256 且不含 , " \r \n）
function AnalyticsService:LogProgressionFailEvent(player, progressionPathName, level, levelName, customData) end

---记录玩家{#0}的进度开始事件，路径{#1}，关卡{#2}，关卡名{#3}，附加数据{#4}
---**适用范围**: 仅服务端
---@param player Player 玩家对象（事件归属，必须在当前 Space 内）
---@param progressionPathName String 进度路径名称（非空，≤50 字符，仅允许 [a-zA-Z0-9_]）
---@param level Any 关卡（number 或 string；string ≤50 字符）
---@param levelName String 关卡名称（可选，≤50 字符）
---@param customData Table 自定义数据（progression 事件允许任意 key；value 支持 str/int/float/bool，str≤256 且不含 , " \r \n）
function AnalyticsService:LogProgressionStartEvent(player, progressionPathName, level, levelName, customData) end

---记录玩家{#0}的自定义蛋码埋点{#1}，数据变化{#2}，附带玩家属性{#3}
---**适用范围**: 仅服务端
---@param player Player 玩家对象（事件归属，必须在当前 Space 内）
---@param eventName String 事件名称（非空，1-12 字符，直接作为蛋码 data_name 上报）
---@param changeNum number 数据变化量
---@param attrKeys? Table 可选附带的玩家属性 key 列表（string[]）；通过 player.Character:GetAttribute(key) 读取，读不到的 key 自动忽略
function AnalyticsService:LogTrackDataChange(player, eventName, changeNum, attrKeys) end

---地图存档信息模块
---**适用范围**: 仅服务端
---@class ArchiveService
---@field AchievementComplete Signal<fun(player: Player, eventId: Int)> 成就完成事件。回调参数：player 玩家, eventId 成就id
---@field AchievementRewardGain Signal<fun(player: Player, eventId: Int)> 成就领取奖励事件。回调参数：player 玩家, eventId 成就id
local ArchiveService = {}

---增加成就进度
---**适用范围**: 仅服务端
---@param player Player 玩家
---@param eventId Int 存档id
---@param addCount Int 增加的进度
function ArchiveService:AddAchievementProgress(player, eventId, addCount) end

---获取成就奖励是否自动领取
---**适用范围**: 仅服务端
---@param eventId Int 成就id
---@return Bool 自动领取
function ArchiveService:GetAchievementAutoGain(eventId) end

---获取成就是否为单局成就
---**适用范围**: 仅服务端
---@param eventId Int 成就id
---@return Bool 单局成就
function ArchiveService:GetAchievementIsSingle(eventId) end

---获取成就进度
---**适用范围**: 仅服务端
---@param player Player 玩家
---@param eventId Int 存档id
---@return Int 进度
function ArchiveService:GetAchievementProgress(player, eventId) end

---获取成就奖励数据
---**适用范围**: 仅服务端
---@param eventId Int 成就id
---@return Table 奖励数据
function ArchiveService:GetAchievementRewards(eventId) end

---获取成就目标次数
---**适用范围**: 仅服务端
---@param eventId Int 成就id
---@return Int 目标次数
function ArchiveService:GetAchievementTargetCount(eventId) end

---获取自定义存档
---**适用范围**: 仅服务端
---@param player Player 玩家
---@param key Int 存档id
---@return Any 存档内容
function ArchiveService:GetCustomArchive(player, key) end

---通过名称获取自定义存档
---**适用范围**: 仅服务端
---@param player Player 玩家
---@param name String 存档名称
---@return Any 存档内容
function ArchiveService:GetCustomArchiveByName(player, name) end

---通过成就id获取存档Id
---**适用范围**: 仅服务端
---@param eventId Int 成就id
---@return Int 自定义存档id
function ArchiveService:GetCustomArchiveIdByAchievementId(eventId) end

---通过名称获取自定义存档id
---**适用范围**: 仅服务端
---@param name String 自定义存档名称
---@return Int 自定义存档id
function ArchiveService:GetCustomArchiveIdByName(name) end

---成就是否完成
---**适用范围**: 仅服务端
---@param player Player 玩家
---@param eventId Int 存档id
---@return Bool 是否完成
function ArchiveService:IsAchievementCompleted(player, eventId) end

---设置成就进度
---**适用范围**: 仅服务端
---@param player Player 玩家
---@param eventId Int 存档id
---@param count Int 存档进度
function ArchiveService:SetAchievementProgress(player, eventId, count) end

---设置自定义存档
---**适用范围**: 仅服务端
---@param player Player 玩家
---@param key Int 存档id
---@param value Any 存档内容
function ArchiveService:SetCustomArchive(player, key, value) end

---通过名称设置自定义存档
---**适用范围**: 仅服务端
---@param player Player 玩家
---@param name String 存档名称
---@param value Any 存档内容
function ArchiveService:SetCustomArchiveByName(player, name, value) end

---AssetService 资产管理服务，提供统一的资产加载、缓存、预加载和状态追踪能力
---@class AssetService : Unit
---@field AssetFetchFailed Signal<fun(uri: String, errorMsg: String)> 资产加载失败时触发。回调参数：uri 失败的资产 URI, errorMsg 错误描述
---@field AssetLoaded Signal<fun(uri: String, result: Any)> 资产加载成功时触发。回调参数：uri 加载的资产 URI, result 加载结果
local AssetService = {}

---同步加载 data 类型资产{#0}
---@param uri String 资产 URI
---@return Any? 数据实例，失败返回 nil
function AssetService:LoadDataAsset(uri) end

---异步加载 data 类型资产{#0}
---@param uri String 资产 URI
---@param callback function 完成回调 function(ok: Bool, dataInstance: table?)
function AssetService:LoadDataAssetAsync(uri, callback) end

---同步加载资产{#0}并创建 Unit 实例
---@param uri String 资产 URI（如 official://preset/{id}、map://xxx）
---@return Unit[] 创建出的 Unit 数组（根在索引 1，失败返回空表）
function AssetService:LoadUnitAsset(uri) end

---异步加载资产{#0}并创建 Unit 实例
---@param uri String 资产 URI
---@param callback function 完成回调 function(ok: Bool, units: Unit[])
function AssetService:LoadUnitAssetAsync(uri, callback) end

---加载资产{#0}并创建 Unit 实例，可用 RootOverride 覆盖根节点
---@param uri String 资产URI
---@param rootOverride? Table 根节点覆盖数据
---@return Unit[] 创建出的 Unit 数组（根在索引 1，已挂到 World，失败返回空表）
function AssetService:LoadUnitAssetByData(uri, rootOverride) end

---批量预加载资产列表{#0}
---@param uriList String[] 资产 URI 列表
---@param callback function 每个资产完成时回调 function(uri: String, status: String)
function AssetService:PreloadAsync(uriList, callback) end

---CameraService 相机管理模块, 控制全局相机信息
---**适用范围**: 客户端和服务端
---@class CameraService : Unit
---@field DefaultCameraPreset Enums.DefaultCameraPresetType 默认相机预设，默认为None，设置为其他预设时会在游戏初始化调整主控相机属性和功能
---@field LiveCamera CameraUnit 当前展示相机, 如果没有相机处于激活状态则为空
---@field MainCamera CameraUnit 主控相机，默认指向当前展示相机(CurrentCamera)，可以手动设置为其他方便标记获取
---@field ResetPitch Bool 相机跟随重置时是否重置俯仰角(pitch)，默认true
---@field ResetYaw Bool 相机跟随重置时是否重置水平朝向(yaw)，默认true
local CameraService = {}

---手动刷新相机, 用于属性变更后需要立刻生效展示的功能
---**适用范围**: 客户端和服务端
function CameraService:ManualRefresh() end

---屏幕坐标转世界射线
---**适用范围**: 客户端和服务端
---@param x Float 屏幕X坐标（像素）
---@param y Float 屏幕Y坐标（像素）
---@param depth? Float 射线起点深度，默认 0
---@return Ray 世界射线
function CameraService:ScreenPointToRay(x, y, depth) end

---设置玩家屏幕震动
---**适用范围**: 客户端和服务端
---@param player Player 玩家
---@param shakeType Enums.CameraShakeType 震动类型
---@param maxAmplitude Float 震动最大幅度
---@param shakeTime Float 震动时间
---@param shakeCurve Enums.CameraShakeCurve 震动曲线
function CameraService:ShakeCamera(player, shakeType, maxAmplitude, shakeTime, shakeCurve) end

---视口坐标转世界射线
---**适用范围**: 客户端和服务端
---@param x Float 视口X坐标 ([0, 1])
---@param y Float 视口Y坐标 ([0, 1])
---@param depth? Float 射线起点深度，默认 0
---@return Ray 世界射线
function CameraService:ViewportPointToRay(x, y, depth) end

---世界坐标转屏幕坐标，供类3DUI功能使用
---**适用范围**: 客户端和服务端
---@param worldPoint Vector3 世界坐标
---@return Vector3 屏幕坐标 (X， Y， Z深度)；Lua 多返回值第二项为 Bool isOnScreen
function CameraService:WorldToScreenPoint(worldPoint) end

---世界坐标转视口坐标（不包含 GUI inset）
---**适用范围**: 客户端和服务端
---@param worldPoint Vector3 世界坐标
---@return Vector3 视口坐标 (X， Y， Z深度)；Lua 多返回值第二项为 Bool isInViewport
function CameraService:WorldToViewportPoint(worldPoint) end

---Camps
---@class Camps : Unit
local Camps = {}

---获取所有阵营
---@return Camp[] 阵营列表
function Camps:GetCamps() end

---云音乐服务，用于在地图中播放网易云音乐曲库中的歌曲，并支持随时切换回地图自身配置的背景音乐。
---@class CloudMusicService : Unit
local CloudMusicService = {}

---播放网易云音乐{#0}，开始时间(秒){#1}，音量比例{#2}
---@param musicID String 云音乐资源ID
---@param seekTime Float 起始播放时间（秒）
---@param volumeScale Float 音量缩放系数
function CloudMusicService:PlayMusic(musicID, seekTime, volumeScale) end

---恢复地图背景音乐
function CloudMusicService:ResumeMapMusic() end

---道具系统
---**适用范围**: 客户端和服务端
---@class CommodityService : Unit
---@field CommodityConsumed Signal<fun(commodityId: Int, consumeNum: Int, consumePlayer: Player)> 回调参数：commodityId 道具Id, consumeNum 数量, consumePlayer 玩家
---@field CommodityObtain Signal<fun(commodityId: Int, consumeNum: Int, consumePlayer: Player, isBringInto: Bool)> 回调参数：commodityId 道具Id, consumeNum 数量, consumePlayer 玩家, isBringInto 是否为跨局携带道具
---@field FanClubStatusChanged Signal<fun(player: Player, oldLevel: Int, newLevel: Int)> 回调参数：player 玩家, oldLevel 变更前等级（0=未加入）, newLevel 变更后等级（0=已退出）
---@field GoodsPurchaseCompleted Signal<fun(goodsId: String, goodsNum: Int, player: Player)> 回调参数：goodsId 商品Id, goodsNum 数量, player 玩家
---@field VipStatusChanged Signal<fun(player: Player, isVip: Bool)> 回调参数：player 玩家, isVip 变更后的会员状态
local CommodityService = {}

---消耗玩家指定数量道具
---**适用范围**: 客户端和服务端
---@param player Player 玩家对象
---@param commodityId Int 道具Id
---@param num Int 消耗数量
function CommodityService:ConsumeCommodity(player, commodityId, num) end

---玩家拥有道具数量
---**适用范围**: 客户端和服务端
---@param player Player 玩家对象
---@param commodityId Int 道具Id
---@return Int 拥有道具数量
function CommodityService:GetCommodityCount(player, commodityId) end

---获取玩家对当前地图创作者的粉丝团等级
---**适用范围**: 客户端和服务端
---@param player Player 玩家对象
---@return Int 粉丝团等级（0=未加入，1/2/3=各级粉丝团）
function CommodityService:GetFanClubLevel(player) end

---获取当前地图所有商品信息列表
---**适用范围**: 客户端和服务端
---@return Any[] 商品信息列表
function CommodityService:GetGoods() end

---获取指定商品的详细信息
---**适用范围**: 客户端和服务端
---@param goodsId String 商品Id
---@return Table 商品信息，不存在时返回nil
function CommodityService:GetGoodsInfo(goodsId) end

---玩家是否拥有道具
---**适用范围**: 客户端和服务端
---@param player Player 玩家对象
---@param commodityId Int 道具Id
---@return Bool 是否拥有道具
function CommodityService:HasCommodity(player, commodityId) end

---查询玩家是否为当前地图作者的粉丝
---**适用范围**: 客户端和服务端
---@param player Player 玩家对象
---@return Bool 是否为粉丝
function CommodityService:IsAuthorFans(player) end

---查询当前地图是否开启了粉丝团权益功能
---**适用范围**: 客户端和服务端
---@return Bool 是否开启
function CommodityService:IsFansRightsActive() end

---查询玩家是否为乐园会员
---**适用范围**: 客户端和服务端
---@param player Player 玩家对象
---@return Bool 是否为乐园会员
function CommodityService:IsVip(player) end

---查询当前地图是否开启了乐园会员权益功能
---**适用范围**: 客户端和服务端
---@return Bool 是否开启
function CommodityService:IsVipRightsActive() end

---提示玩家加入/升级粉丝团
---**适用范围**: 客户端和服务端
---@param player Player 玩家对象
function CommodityService:PromptFanClubPurchase(player) end

---提示玩家开通乐园会员
---**适用范围**: 客户端和服务端
---@param player Player 玩家对象
function CommodityService:PromptVipPurchase(player) end

---获取免费商品
---**适用范围**: 客户端和服务端
---@param player Player 玩家对象
---@param rawGoodsId String 商品Id
function CommodityService:RequestFreeGoods(player, rawGoodsId) end

---设置付费道具商店可见性
---**适用范围**: 客户端和服务端
---@param player Player 玩家对象
---@param visible Bool 可见性
function CommodityService:SetGoodsPanelVisible(player, visible) end

---设置付费商品可见性
---**适用范围**: 客户端和服务端
---@param player Player 玩家对象
---@param rawGoodsId String 商品Id
---@param visible Bool 可见性
function CommodityService:SetGoodsVisible(player, rawGoodsId, visible) end

---玩家显示指定商品详情界面
---**适用范围**: 客户端和服务端
---@param player Player 玩家对象
---@param rawGoodsId String 商品Id
function CommodityService:ShowGoodsDetailPanel(player, rawGoodsId) end

---玩家显示指定商品购买界面
---**适用范围**: 客户端和服务端
---@param player Player 玩家对象
---@param rawGoodsId String 商品Id
---@param showTime Float 展示时间
function CommodityService:ShowGoodsPurchasePanel(player, rawGoodsId, showTime) end

---配置服务（仅服务端）。提供面向地图作者的高阶 API：
---- GetConfigAsync(): 拉取最新已发布配置，返回 ConfigSnapshot
---- GetConfigForPlayerAsync(player): 在 GetConfigAsync 基础上叠加按玩家分桶的覆盖
---- SetTestingValue / ClearTestingValue: 在试玩模式下覆盖某个配置值
---仅由 game:GetService("ConfigService") 返回，不可实例化。
---**适用范围**: 仅服务端
---@class ConfigService : Unit
local ConfigService = {}

---清除测试覆盖值（仅试玩模式生效）
---**适用范围**: 仅服务端
---@param key String 配置键名
function ConfigService:ClearTestingValue(key) end

---异步获取最新已发布配置快照
---**适用范围**: 仅服务端
---@return ConfigSnapshot 配置快照
function ConfigService:GetConfigAsync() end

---异步获取面向特定玩家的配置快照
---**适用范围**: 仅服务端
---@param player Player 玩家对象
---@return ConfigSnapshot 配置快照（携带玩家分桶信息）
function ConfigService:GetConfigForPlayerAsync(player) end

---在试玩模式下临时覆盖某个 key 的返回值；非编辑器模式直接 return
---**适用范围**: 仅服务端
---@param key String 配置键名
---@param value Any 覆盖值
function ConfigService:SetTestingValue(key, value) end

---CustomAppearanceService 自定义外观运行时管理
---@class CustomAppearanceService : Unit
local CustomAppearanceService = {}

---运行时创建自定义外观，返回自定义外观对象ID
---@param data CustomAppearance 外观数据
---@return String 自定义外观对象ID
function CustomAppearanceService:CreateCustomAppearance(data) end

---数据存储服务，用于数据持久化存储和玩家存档管理。
---仅由 game:GetService("DataStoreService") 返回，不可实例化。
---**适用范围**: 仅服务端
---@class DataStoreService : Unit
local DataStoreService = {}

---获取普通数据存储集合
---**适用范围**: 仅服务端
---@param name String 集合名称
---@param scope? String 前置域, 默认 global
---@param options? DataStoreOptions 获取DataStore的额外选项, 可通过 DataStoreOptions.New() 创建
---@return DataStore 数据存储集合
function DataStoreService:GetDataStore(name, scope, options) end

---获取全局数据存储集合 (等价于 GetDataStore("", "global", options))
---**适用范围**: 仅服务端
---@param options? DataStoreOptions 获取DataStore的额外选项, 可通过 DataStoreOptions.New() 创建
---@return DataStore 全局数据存储集合
function DataStoreService:GetGlobalDataStore(options) end

---获取有序数据存储集合
---**适用范围**: 仅服务端
---@param name String 集合名称
---@param scope? String 前置域, 默认 global
---@param options? DataStoreOptions 获取DataStore的额外选项, 可通过 DataStoreOptions.New() 创建
---@return OrderedDataStore 有序数据存储集合
function DataStoreService:GetOrderedDataStore(name, scope, options) end

---分页列出所有普通 DataStore 集合
---**适用范围**: 仅服务端
---@param prefix? String 名称前缀过滤, 默认空字符串
---@param pageSize? Int 页大小, 默认 0 (使用服务端默认值)
---@param cursor? String 分页游标
---@param options? DataStoreListOptions 可选参数, 可通过 DataStoreListOptions.New() 创建
---@return DataStoreInfoPages 分页迭代器
function DataStoreService:ListDataStoresAsync(prefix, pageSize, cursor, options) end

---分页列出所有有序 OrderedDataStore 集合
---**适用范围**: 仅服务端
---@param prefix? String 名称前缀过滤, 默认空字符串
---@param pageSize? Int 页大小, 默认 0 (使用服务端默认值)
---@param cursor? String 分页游标
---@param options? DataStoreListOptions 可选参数, 可通过 DataStoreListOptions.New() 创建
---@return DataStoreInfoPages 分页迭代器
function DataStoreService:ListOrderedDataStoresAsync(prefix, pageSize, cursor, options) end

---特效服务
---**适用范围**: 客户端和服务端
---@class EffectService : Unit
local EffectService = {}

---播放本地特效{#0}，位置{1}，旋转{#2}，缩放{#3}
---**适用范围**: 客户端和服务端
---@param effectId String 特效资源 URI（仅 official://effect/{path} 或 custom://{asset_id}）
---@param position Vector3 世界坐标位置（默认 0,0,0）
---@param rotation Quaternion 旋转（默认单位四元数）
---@param scale Vector3 缩放（默认 1,1,1）
---@param keepTime? Float 自动销毁延时秒（默认 -1 不自动销毁）
---@param loop? Bool 是否循环（默认 false）
---@param isAsync? Bool 是否异步加载（默认 false 同步，true 时不阻塞主线程）
---@return Any EffectHandle（特效句柄引用）
function EffectService:PlayLocalEffect(effectId, position, rotation, scale, keepTime, loop, isAsync) end

---好友服务，用于在游戏内查询玩家之间的好友关系，并向其他玩家发起加好友请求。
---@class FriendShipService
local FriendShipService = {}

---指定玩家执行添加好友操作
---@param player Player 指定玩家，必须在当前场景中
---@param userId String 目标玩家的UserId
function FriendShipService:AddFriendWith(player, userId) end

---异步查询指定玩家是否是指定UserId的好友
---@param player Player 指定玩家，必须在当前场景中
---@param userId String 目标玩家的UserId
---@param checkCallback function 查询结果回调函数
function FriendShipService:IsPlayerFriendsWithAsync(player, userId, checkCallback) end

---Game是游戏对象树的根节点，继承自Unit。作为全局唯一的顶层对象，承载所有服务和单位的创建与管理。通过 GetService 获取各类全局服务，通过 CreateUnit 创建新的单位实例。
---@class Game : Unit
---@field Loaded Signal<fun()> 客户端初始单位/属性加载完成时触发，仅触发一次（幂等保护）。服务端不会触发该信号。订阅者通过 game.Loaded:Connect(fn) 接收回调，回调不带任何参数。
---@field ServerRestartScheduled Signal<fun(restartTime: Int, closeReason: Enums.SpaceCloseReason, attributes: Table)> 当服务器被计划重启或当官方服务器需要执行官方维护更新时，以使用此事件通知服务器上的玩家即将发生的 重启。回调参数：restartTime 计划重启的时间戳,实际重启可能会稍晚于此预计时间，但不会早于此时间, closeReason 触发服务器重启的原因,参见枚举Enum.SpaceCloseReason, attributes 提供的重启事件自定义元数据，根据它可以定制特殊的逻辑，默认是一个空的字典
local Game = {}

---绑定一个在服务器关闭之前调用的函数。如果绑定的函数接受一个参数，则传递Enum.CloseReason，指定服务器关闭的原因。可以通过反复调用BindToClose()。服务器在关闭之前等待30秒，以便所有绑定的函数停止运行。30秒后，服务器即使函数仍在运行，也会关闭。
---@param callback function 如果绑定的函数接受一个参数，则传递Enum.CloseReason，指定服务器关闭的原因。
function Game:BindToClose(callback) end

---按类型创建一个新的单位实例，并可通过 values 参数指定初始属性。这是全局唯一的单位创建入口，承载真正的创建逻辑：World:CreateUnit 等接口本质上都是对本方法的封装（语法糖），最终都会调用 game:CreateUnit(unitType, values) 完成创建。与 World:CreateUnit 不同，本方法不会自动为单位设置 Parent，需在 values 中显式指定，否则新单位不会挂载到对象树上。
---@param unitType String 要创建的单位类型名称，如 "WorldUnit"、"ModelUnit"、"EffectUnit" 等
---@param values? Table 初始化属性键值表。可填写的属性键来自对应 unitType 的 API 文档（即该类型及其继承链上声明的属性），例如 { Name = "box", Position = Vector3.new(0, 10, 0), Parent = world }。注意：UnitId 为系统保留键，传入会被忽略；本方法不会自动设置 Parent，需显式指定。具体支持哪些属性以该单位类型 API 文档中列出的属性为准。
---@return Unit? 新创建的单位实例，创建失败时返回 nil
function Game:CreateUnit(unitType, values) end

---生成一个全局唯一GUID。
---@return String 唯一编号
function Game:GenerateGUID() end

---按名称获取全局服务实例，如 PhysicsService、CollectionService 等
---@overload fun(self: Game, serviceName: "AdvertisementService"): AdvertisementService
---@overload fun(self: Game, serviceName: "AnalyticsService"): AnalyticsService
---@overload fun(self: Game, serviceName: "ArchiveService"): ArchiveService
---@overload fun(self: Game, serviceName: "AssetService"): AssetService
---@overload fun(self: Game, serviceName: "CameraService"): CameraService
---@overload fun(self: Game, serviceName: "Camps"): Camps
---@overload fun(self: Game, serviceName: "CloudMusicService"): CloudMusicService
---@overload fun(self: Game, serviceName: "CommodityService"): CommodityService
---@overload fun(self: Game, serviceName: "ConfigService"): ConfigService
---@overload fun(self: Game, serviceName: "CustomAppearanceService"): CustomAppearanceService
---@overload fun(self: Game, serviceName: "DataStoreService"): DataStoreService
---@overload fun(self: Game, serviceName: "EffectService"): EffectService
---@overload fun(self: Game, serviceName: "FriendShipService"): FriendShipService
---@overload fun(self: Game, serviceName: "LightingService"): LightingService
---@overload fun(self: Game, serviceName: "LogService"): LogService
---@overload fun(self: Game, serviceName: "MapData"): MapData
---@overload fun(self: Game, serviceName: "MemoryStoreService"): MemoryStoreService
---@overload fun(self: Game, serviceName: "MessageService"): MessageService
---@overload fun(self: Game, serviceName: "PathfindingService"): PathfindingService
---@overload fun(self: Game, serviceName: "PhysicsService"): PhysicsService
---@overload fun(self: Game, serviceName: "Players"): Players
---@overload fun(self: Game, serviceName: "PrimitiveService"): PrimitiveService
---@overload fun(self: Game, serviceName: "ProfileService"): ProfileService
---@overload fun(self: Game, serviceName: "ReplicatedFirst"): ReplicatedFirst
---@overload fun(self: Game, serviceName: "ReplicatedStorage"): ReplicatedStorage
---@overload fun(self: Game, serviceName: "RunService"): RunService
---@overload fun(self: Game, serviceName: "SceneGui"): SceneGui
---@overload fun(self: Game, serviceName: "SocialService"): SocialService
---@overload fun(self: Game, serviceName: "SoundService"): SoundService
---@overload fun(self: Game, serviceName: "StarterGui"): StarterGui
---@overload fun(self: Game, serviceName: "StoryService"): StoryService
---@overload fun(self: Game, serviceName: "TagService"): TagService
---@overload fun(self: Game, serviceName: "Task"): Task
---@overload fun(self: Game, serviceName: "TeleportService"): TeleportService
---@overload fun(self: Game, serviceName: "TextChatService"): TextChatService
---@overload fun(self: Game, serviceName: "TimerService"): TimerService
---@overload fun(self: Game, serviceName: "TweenService"): TweenService
---@overload fun(self: Game, serviceName: "UserInputService"): UserInputService
---@overload fun(self: Game, serviceName: "VibrationService"): VibrationService
---@overload fun(self: Game, serviceName: "World"): World
---@param serviceName String 要获取的服务名称，如 "PhysicsService"、"CollectionService" 等
---@return Unit? 对应的服务实例对象
function Game:GetService(serviceName) end

---客户端初始单位/属性加载完成时触发 Loaded 信号，本方法返回当前是否已触发。服务端不会触发 Loaded，故服务端恒返回 false。
---@return Bool 是否已完成初始加载
function Game:IsLoaded() end

---将指定文本复制到当前客户端设备的剪切板，写入后可通过 Ctrl+V 粘贴到别处。仅客户端有效，服务端调用静默返回。
---@param text String 要复制到剪切板的字符串。
function Game:SetClipboardText(text) end

---光照服务
---**适用范围**: 客户端和服务端
---@class LightingService : Unit
---@field AmbientColor Color 环境光颜色
---@field AmbientIntensity Float 环境光强度
---@field Color Color 主光源颜色
---@field EnvironmentMap String 场景反射立方体贴图
---@field FilmicTonemapEnabled Bool 电影色调映射
---@field Intensity Float 主光源强度
---@field Orientation Vector3 主光源朝向
---@field ShadowFade Float 阴影淡化
local LightingService = {}

---LogService 日志服务
---**适用范围**: 客户端和服务端
---@class LogService : Unit
---@field MessageOut Signal<fun(message: string, messageType: Enums.MessageType)> 回调参数：message 日志消息内容, messageType 日志类型枚举值
local LogService = {}

---**适用范围**: 客户端和服务端
function LogService:ClearOutput() end

---**适用范围**: 客户端和服务端
---@param message string 日志消息
---@param context? Table 结构化上下文数据
function LogService:Error(message, context) end

---**适用范围**: 客户端和服务端
---@return LogRecord[] 历史记录数组，每条包含 message， messageType， timestamp， context
function LogService:GetLogHistory() end

---**适用范围**: 客户端和服务端
---@param message string 日志消息
---@param context? Table 结构化上下文数据
function LogService:Info(message, context) end

---**适用范围**: 客户端和服务端
---@param messageType Enums.MessageType 日志类型枚举值
---@param message string 日志消息
---@param context? Table 结构化上下文数据
function LogService:Log(messageType, message, context) end

---**适用范围**: 客户端和服务端
---@param message string 日志消息
---@param context? Table 结构化上下文数据
function LogService:Output(message, context) end

---**适用范围**: 客户端和服务端
---@param message string 日志消息
---@param context? Table 结构化上下文数据
function LogService:Warn(message, context) end

---MapData 用于管理地图数据
---@class MapData : Unit
local MapData = {}

---获取用户自定义地图数据。
---@param key String 用户自定义地图数据的 key
function MapData:GetCustomMapData(key) end

---内存存储服务（仅服务端可用），提供三种集合：SortedMap / Queue / HashMap；SortedMap & HashMap 支持基于 transform 回调的原子 UpdateAsync。
---仅由 game:GetService("MemoryStoreService") 返回，不可实例化。
---**适用范围**: 仅服务端
---@class MemoryStoreService : Unit
local MemoryStoreService = {}

---获取哈希集合 (HashMap) 句柄；每次返回新实例
---**适用范围**: 仅服务端
---@param name String 集合名称
---@return MemoryStoreHashMap 哈希集合句柄
function MemoryStoreService:GetHashMap(name) end

---获取队列集合 (Queue) 句柄；每次返回新实例
---**适用范围**: 仅服务端
---@param name String 集合名称
---@param queueInvisibleExpireSecs? Int 队列级默认不可见窗口秒数；后续 ReadAsync 在 options 未指定 QueueInvisibleExpireSecs 时使用该值；不传时默认 30
---@return MemoryStoreQueue 队列集合句柄
function MemoryStoreService:GetQueue(name, queueInvisibleExpireSecs) end

---获取有序集合 (SortedMap) 句柄；每次返回新实例，集合本身轻量、不做缓存
---**适用范围**: 仅服务端
---@param name String 集合名称
---@return MemoryStoreSortedMap 有序集合句柄
function MemoryStoreService:GetSortedMap(name) end

---MessagingService 允许同一地图的不同服务器之间实时通信，使用主题隔离。主题是开发者定义的字符串（1-80 个字符），服务器使用这些字符串发送和接收消息。交付是尽力而为的，并不保证。
---**适用范围**: 仅服务端
---@class MessageService : Unit
local MessageService = {}

---**适用范围**: 仅服务端
---@param topic String 主题的长度限制: 1-80个字符, 否则将引发错误
---@param message Any 注意: 序列化后大小不能超过1k字节, 否则将引发错误
function MessageService:PublishAsync(topic, message) end

---**适用范围**: 仅服务端
---@param topic String 主题的长度限制: 1-80个字符, 否则将引发错误
---@param callback function function(message); 注意: 该函数不能是异步函数
---@return Connection 与信号之间的连接器，可用于取消订阅
function MessageService:SubscribeAsync(topic, callback) end

---PathfindingService 寻路服务，用于加载导航网格并生成寻路路径
---**适用范围**: 客户端和服务端
---@class PathfindingService : Unit
---@field HasDynamicNavMesh Bool 为 false 时不会启用运行时动态 NavMesh 更新：不会监听运行时 WorldUnit/PathfindingLink/PathfindingModifier 变化，不会按脏 tile 重新烘焙与同步 _navmesh_tile_versions，Path.Blocked/Unblocked 也不会因动态烘焙后的阻断检测而触发；编辑器预摆并已参与烘焙的物体不受此限制
---@field HasNavMesh Bool 当前空间是否存在有效的导航网格
local PathfindingService = {}

---加载导航网格并创建一个新的路径对象，后续可调用 Path:ComputeAsync 计算具体路径
---**适用范围**: 客户端和服务端
---@param args? Table 支持字段：AgentCanClimb(Bool，可选，默认 true)：是否允许路径经过可攀爬/跳跃等 OffMesh 连接；AgentRadius(Float，可选)：寻路代理半径，传给底层 find_path 影响路径搜索；Costs(Map，可选，默认 {})：区域代价表，格式为 {区域标签(String): 代价(Float)}，代价越高越倾向绕开该区域。当前 Path 实现仅使用以上字段，其他字段会被透传但不会生效
---@return Path 返回的路径对象
function PathfindingService:CreatePath(args) end

---PhysicsService包含碰撞组操作和物理空间查询方法, 通过 game:GetService('PhysicsService') 获取单例。
---@class PhysicsService : Unit
---@field ContinuousCollisionEnabled Bool 物理连续碰撞检测开关
local PhysicsService = {}

---方块形状投射
---@param cframe CFrame 方块位置与朝向
---@param size Vector3 方块尺寸
---@param direction Vector3 投射方向(长度=最大距离)
---@param raycastParams? RaycastParams 过滤参数(可选)
---@return RaycastResult? 命中结果(无命中返回nil)
function PhysicsService:Blockcast(cframe, size, direction, raycastParams) end

---设置两碰撞组是否可碰撞
---@param name1 String 碰撞组名称1
---@param name2 String 碰撞组名称2
---@param collidable Bool 是否可碰撞
function PhysicsService:CollisionGroupSetCollidable(name1, name2, collidable) end

---查询两碰撞组是否可碰撞
---@param name1 String 碰撞组名称1
---@param name2 String 碰撞组名称2
---@return Bool 是否可碰撞
function PhysicsService:CollisionGroupsAreCollidable(name1, name2) end

---获取碰撞组的可碰撞目标组字典
---@param collisionGroupName String 碰撞组名称
function PhysicsService:GetCollisionWithGroupDict(collisionGroupName) end

---获取引擎预留碰撞组
---@return String[] 引擎预留碰撞组名称列表
function PhysicsService:GetEngineRegisteredCollisionGroups() end

---返回 AABB 与给定 OBB 重叠的 Unit 列表。查询体积由 cframe 与 size 定义的 OBB 给出, 命中判定基于目标 Unit 的轴对齐包围盒(AABB)而非其真实几何体积, 返回结果不保证按距离排序。
---@param cframe CFrame OBB位姿
---@param size Vector3 OBB尺寸
---@param overlapParams? OverlapParams 过滤参数(可选)
---@return Unit[] AABB与OBB重叠的Unit列表
function PhysicsService:GetPartBoundsInBox(cframe, size, overlapParams) end

---返回 AABB 与给定球体重叠的 Unit 列表。查询体积由 position 与 radius 定义的球体给出, 命中判定基于目标 Unit 的轴对齐包围盒(AABB)而非其真实几何体积, 返回结果不保证按距离排序。
---@param position Vector3 球心位置
---@param radius Float 球半径
---@param overlapParams? OverlapParams 过滤参数(可选)
---@return Unit[] AABB与球重叠的Unit列表
function PhysicsService:GetPartBoundsInRadius(position, radius, overlapParams) end

---返回与 part 碰撞形状精确重叠的 Unit 列表。本方法对碰撞形状做完整几何重叠检测, 返回结果不保证按距离排序。
---@param part Unit 参与检测的参考Unit
---@param overlapParams? OverlapParams 过滤参数(可选)
---@return Unit[] 与part碰撞形状精确重叠的Unit列表
function PhysicsService:GetPartsInPart(part, overlapParams) end

---获取所有已注册碰撞组
---@return String[] 碰撞组名称列表
function PhysicsService:GetRegisteredCollisionGroups() end

---获取用户注册碰撞组
---@return String[] 用户碰撞组名称列表
function PhysicsService:GetUserRegisteredCollisionGroups() end

---射线检测
---@param origin Vector3 射线起点
---@param direction Vector3 射线方向(长度=最大距离)
---@param raycastParams? RaycastParams 射线过滤参数(可选)
---@return RaycastResult? 射线检测结果(无命中返回nil)
function PhysicsService:Raycast(origin, direction, raycastParams) end

---注册碰撞组
---@param name String 碰撞组名称
function PhysicsService:RegisterCollisionGroup(name) end

---形状投射
---@param part Unit 进行检测的部件
---@param direction Vector3 投射方向(长度=最大距离)
---@param raycastParams? RaycastParams 过滤参数(可选)
---@return RaycastResult? 命中结果(无命中返回nil)
function PhysicsService:Shapecast(part, direction, raycastParams) end

---球形投射
---@param position Vector3 球心位置
---@param radius Float 球半径
---@param direction Vector3 投射方向(长度=最大距离)
---@param raycastParams? RaycastParams 过滤参数(可选)
---@return RaycastResult? 命中结果(无命中返回nil)
function PhysicsService:Spherecast(position, radius, direction, raycastParams) end

---玩家服务，是当前局内所有玩家对象的容器与管理入口，提供玩家枚举与查找，玩家加入和离开的事件等。客户端额提供LocalPlayer用于获取本地玩家
---**适用范围**: 客户端和服务端
---@class Players : Unit
---@field CharacterAutoLoads Bool 控制游戏是否自动加载玩家单位
---@field LocalPlayer Player 仅客户端，获取本地玩家对象
---@field PlayerAdded Signal<fun(player: Player)> 当有新玩家加入时触发。回调参数：player 玩家
---@field PlayerRemoving Signal<fun(player: Player)> 当有玩家即将离开时触发。回调参数：player 玩家
local Players = {}

---获取指定玩家的昵称（失败抛错，需 pcall 包裹）
---**适用范围**: 客户端和服务端
---@param userId String 玩家编号
---@return String 玩家昵称
function Players:GetNameFromUserIdAsync(userId) end

---通过玩家编号获取玩家对象
---**适用范围**: 客户端和服务端
---@param userId String 玩家编号
---@return Player? 玩家
function Players:GetPlayerByUserId(userId) end

---通过角色获取玩家对象
---**适用范围**: 客户端和服务端
---@param character EggyUnit 角色对象
---@return Player? 玩家
function Players:GetPlayerFromCharacter(character) end

---获取所有在线玩家列表
---**适用范围**: 客户端和服务端
---**示例**:
---```lua
---for userId, player in game:GetService("Players"):GetPlayers() do print(userId, player) end
---```
---@return Player[] 所有玩家列表
function Players:GetPlayers() end

---获取指定玩家的头像框
---**适用范围**: 客户端和服务端
---@param userId String 玩家编号
---@return String 头像框 avatarframe:// 协议地址，可直接交给 EUIImage:SetImage 渲染；失败返回空串
---@return Bool 是否成功取到头像框
function Players:GetUserAvatarFrame(userId) end

---获取指定玩家的头像缩略图
---**适用范围**: 客户端和服务端
---@param userId String 玩家编号
---@param thumbnailType Enums.ThumbnailType 头像类型
---@param thumbnailSize Enums.ThumbnailSize 头像尺寸
---@return String 头像 avatar:// 协议地址，可直接交给 EUIImage:SetImage 渲染；失败返回空串
---@return Bool 是否成功取到头像
function Players:GetUserThumbnailAsync(userId, thumbnailType, thumbnailSize) end

---设置聊天显示样式
---**适用范围**: 客户端和服务端
---@param chatStyle Enums.ChatStyle 聊天显示样式
function Players:SetChatStyle(chatStyle) end

---PrimitiveService SE 客户端图元渲染统一入口，提供图元创建/销毁、位置与可见性控制，及抛物线绘制
---**适用范围**: 仅客户端
---@class PrimitiveService : Unit
local PrimitiveService = {}

---创建一个图元，返回图元句柄，后续通过句柄操作该图元
---**适用范围**: 仅客户端
---@return Int 图元句柄 handle
function PrimitiveService:CreatePrimitive() end

---销毁图元，从场景移除并清理资源
---**适用范围**: 仅客户端
---@param handle Int 图元句柄
function PrimitiveService:DestroyPrimitive(handle) end

---一键绘制抛物线
---**适用范围**: 仅客户端
---@param handle Int 图元句柄
---@param opts Table 可选参数 { startPos: Vector3(必填), velocity: Vector3(必填), gravity: Vector3(必填), totalTime: Float?(默认2.0), stepTime: Float?(默认0.08), width: Float?(默认0.3), raycastParams: RaycastParams? }
---@return Bool 是否命中障碍
---@return Vector3 终点世界坐标
function PrimitiveService:DrawParabola(handle, opts) end

---性能监控服务
---**适用范围**: 客户端和服务端
---@class ProfileService : Unit
local ProfileService = {}

---将采集到的Lua性能数据导出为火焰图HTML（含CPU栈、覆盖率与内存diff面板）。文件写入当前进程工作目录。仅编辑器试玩态可用
---**适用范围**: 客户端和服务端
---@param filePath String 如 "lua_dump.html"
---@return Bool 是否成功导出
function ProfileService:DumpLuaProfileStacks(filePath) end

---Error
---**适用范围**: 客户端和服务端
---@param msg Any 消息内容
function ProfileService:Error(msg) end

---获取场景热力图数据
---**适用范围**: 仅客户端
---@return Table 热力图数据 {model_prim_num， model_dp_num， prim_num， dp_num， fx_dp_num， logic_rate， render_rate， ts}；仅客户端有数据，服务端无渲染数据返回空表
function ProfileService:GetSceneProfileData() end

---Print
---**适用范围**: 客户端和服务端
---@param msg Any 消息内容
function ProfileService:Print(msg) end

---开始一段代码计时
---**适用范围**: 客户端和服务端
---@param name String 计时标签名
function ProfileService:ProfileBegin(name) end

---结束最近一段计时
---**适用范围**: 客户端和服务端
---@return number 最近一段计时耗时（毫秒），无匹配开始段返回 0
function ProfileService:ProfileEnd() end

---开始采集Lua CPU火焰图，并捕获当前内存分配树快照作为基线。
---推荐用法：
---1. StartMemoryRecord()：尽早调用，开始记录内存分配
---2. StartLuaProfile()：开始采集CPU火焰图
---3. 需要时 StopLuaProfile()：结束采集（同时计算内存diff）
---4. DumpLuaProfileStacks("lua_dump.html")：导出火焰图HTML查看
---仅编辑器试玩态可用
---**适用范围**: 客户端和服务端
---@return Bool 是否成功开始
function ProfileService:StartLuaProfile() end

---开始记录Lua内存分配树，供StartLuaProfile采集期间的内存diff使用，建议在脚本启动早期调用。仅编辑器试玩态可用
---**适用范围**: 客户端和服务端
---@return Bool 是否成功开始
function ProfileService:StartMemoryRecord() end

---结束Lua CPU火焰图采集，同时捕获内存end快照并计算diff。仅编辑器试玩态可用
---**适用范围**: 客户端和服务端
---@return Bool 是否成功结束
function ProfileService:StopLuaProfile() end

---停止记录Lua内存分配树。仅编辑器试玩态可用
---**适用范围**: 客户端和服务端
---@return Bool 是否成功停止
function ProfileService:StopMemoryRecord() end

---Warn
---**适用范围**: 客户端和服务端
---@param msg Any 消息内容
function ProfileService:Warn(msg) end

---优先复制服务容器。其下的子单位会在客户端加入时最先被复制，适用于存放需要在游戏加载初期就可用的关键资源（如加载界面脚本、初始化配置等）。通过 game:GetService('ReplicatedFirst') 访问。
---@class ReplicatedFirst : Unit
local ReplicatedFirst = {}

---共享复制服务容器。其下的子单位会被自动同步到所有客户端，但不会为其创建物理刚体和渲染模型，适用于存放服务端与客户端共享的数据对象（如 RemoteEvent、配置数据、共用模块脚本等）。通过 game:GetService('ReplicatedStorage') 访问。
---@class ReplicatedStorage : Unit
local ReplicatedStorage = {}

---运行时服务，提供帧循环各阶段的时序事件，并用于判断当前代码所处的运行环境（客户端、服务端或编辑器试玩）。
---@class RunService : Unit
---@field FrameUpdate Signal<fun(deltaTime: Float)> 每帧逻辑帧更新时触发。回调参数：deltaTime 逻辑帧时间长
---@field Heartbeat Signal<fun(deltaTime: Float, maxTaskCount: Int)> 每帧逻辑帧更新时触发。回调参数：deltaTime 逻辑帧时间长, maxTaskCount 最大任务数
---@field PostFrameUpdate Signal<fun(deltaTime: Float)> 每帧逻辑帧更新完成后触发。回调参数：deltaTime 逻辑帧时间长
---@field PostSimulation Signal<fun(deltaTimeSim: Float)> 每帧在物理模拟完成后触发。回调参数：deltaTimeSim 物理步长
---@field PreSimulation Signal<fun(deltaTimeSim: Float)> 每帧在物理模拟前触发。回调参数：deltaTimeSim 物理步长
local RunService = {}

---判断当前是否在客户端环境运行
---@return Bool 是否是客户端
function RunService:IsClient() end

---判断当前是否在服务端环境运行
---@return Bool 是否是服务端
function RunService:IsServer() end

---判断当前是否在编辑器试玩环境
---@return Bool 是否是编辑器试玩环境
function RunService:IsStudio() end

---等待VSCode调试器连接（编辑器会卡住直到连接成功），此功能仅PC编辑器可用
function RunService:WaitForDebugger() end

---SceneGui 用于管理场景UI系统，在3D世界坐标中创建和管理UI元素
---**适用范围**: 客户端和服务端
---@class SceneGui : Unit
---@field EuiManager EUIManager EUI 管理器
local SceneGui = {}

---在指定世界坐标创建场景UI节点
---**适用范围**: 客户端和服务端
---@param position Vector3 3D世界坐标位置
---@param nodeInfo? Table 可选的节点配置信息
---@return EUISceneNode 创建的场景UI节点；EuiManager不存在时返回nil
function SceneGui:CreateSceneNodeAtPosition(position, nodeInfo) end

---在指定单位的挂点创建场景UI节点
---**适用范围**: 客户端和服务端
---@param Unit Unit 挂接单位
---@param Socket String 挂点名称
---@param Offset Vector3 相对挂点的偏移
---@param InheritVisible Bool 是否跟随单位可见性
---@param nodeInfo? Table 可选的节点配置信息
---@return EUISceneNode 创建的场景UI节点；EuiManager不存在时返回nil
function SceneGui:CreateSceneNodeAttachUnit(Unit, Socket, Offset, InheritVisible, nodeInfo) end

---社交服务，好友邀请面板、分享面板，以及基于 PartyId 的队伍信息查询能力。
---**适用范围**: 客户端和服务端
---@class SocialService : Unit
local SocialService = {}

---异步查询给定 partyId 的队伍成员信息字典，返回形如 { [UserId] = { mmo_map_id, server_instance_id, reserved_server_access_code } } 的表。partyId 为空字符串时返回空表。
---**适用范围**: 仅服务端
---@param partyId String 队伍 Id
---@return Table? 队伍成员信息字典 { [UserId] = { mmo_map_id， server_instance_id， reserved_server_access_code } }
function SocialService:GetPartyAsync(partyId) end

---仅返回当前 Space 内在线且 PartyId 相同的 Player 数组。
---**适用范围**: 仅服务端
---@param partyId String 队伍 Id
---@return Player[]? 同队伍的在线玩家列表
function SocialService:GetPlayersByPartyId(partyId) end

---声音服务
---**适用范围**: 客户端和服务端
---@class SoundService : Unit
---@field GroupVolumeChanged Signal<fun(name: String, volume: Float)> 音组音量变化。回调参数：name 音组名称, volume 新音量值（0~100）
local SoundService = {}

---获取音组{#0}的音量
---**适用范围**: 客户端和服务端
---@param name String 音组名称
---@return Float 音量（0~100），音组不存在返回 100
function SoundService:GetGroupVolume(name) end

---播放{#0}，持续时间{#5}，音量大小{#1}, 播放速率{#2}, 额外属性皆填False:{#3}{#4}
---**适用范围**: 客户端和服务端
---@param soundId String 声音ID
---@param volume Float 音量
---@param speed Float 速率
---@param playerOrCampRoleId Bool player对象
---@param campRoleId Bool 阵营角色ID
---@param duration Float 播放时长
---@return SoundUnit 音效组件
function SoundService:Play2D(soundId, volume, speed, playerOrCampRoleId, campRoleId, duration) end

---在{#1}播放{#0}，持续时间{#2}，音量大小{#3}, 播放速率{#4}, 额外属性皆填False:
---**适用范围**: 客户端和服务端
---@param soundId String 声音 ID
---@param position Vector3 声音位置（Vector3 或同结构）
---@param duration Float 播放时长
---@param volume Float 音量 0~100
---@param speed Float 速率 0~1
---@param player Bool player对象
---@return SoundUnit 音效组件
function SoundService:Play3D(soundId, position, duration, volume, speed, player) end

---本地一次性播放 2D 音效（不创建 Unit，性能开销最小）
---**适用范围**: 客户端和服务端
---@param soundId String 声音资源 URI（official://audio/{id} 或 custom://{asset_id}）
---@param volume Float 音量 0~100
---@param speed Float 速率 0~1
function SoundService:PlayLocalSound(soundId, volume, speed) end

---设置音组{#0}的音量为{#1}
---**适用范围**: 客户端和服务端
---@param name String 音组名称
---@param volume Float 音量（0~100）
function SoundService:SetGroupVolume(name, volume) end

---StarterGui 用于管理UI界面系统
---@class StarterGui : Unit
local StarterGui = {}

---获取自定义Core UI参数的值
---@param parameterName String 参数名称
function StarterGui:GetCore(parameterName) end

---获取CoreGui元素的启用状态
---@param coreGuiType Enums.CoreGuiType CoreGui类型
function StarterGui:GetCoreGuiEnabled(coreGuiType) end

---设置自定义Core UI参数
---@param parameterName String 参数名称
---@param value Any 参数值
function StarterGui:SetCore(parameterName, value) end

---设置CoreGui元素的启用状态
---@param coreGuiType Enums.CoreGuiType CoreGui类型
---@param enabled Bool 是否启用
function StarterGui:SetCoreGuiEnabled(coreGuiType, enabled) end

---剧情对话播放服务，提供剧情开始、停止、跳过、状态查询等接口，供地图作者控制玩家播放地图中配置的剧情对话，并提供剧情开始、结束、跳过三个信号供订阅剧情生命周期事件。用法示例：game:GetService('StoryService'):StartStory(player, storyID)
---**适用范围**: 客户端和服务端
---@class StoryService : Unit
---@field OnStoryEnd Signal<fun(player: Player, storyID: String)> 当玩家当前剧情正常结束时触发（仅服务端）。回调参数：player 结束剧情的玩家。, storyID 本次结束的剧情 ID。
---@field OnStorySkip Signal<fun(player: Player, storyID: String)> 当玩家主动跳过当前剧情时触发（仅服务端）。与 OnStoryEnd 的区别：跳过属于玩家主动操作（例如点击跳过按钮），不触发剧情配表中配置的结束事件。回调参数：player 跳过剧情的玩家。, storyID 本次跳过的剧情 ID。
---@field OnStoryStart Signal<fun(player: Player, storyID: String)> 当玩家开始播放某剧情时触发（仅服务端）。回调参数：player 开始播放剧情的玩家。, storyID 本次开始的剧情 ID，对应地图剧情配表中的剧情条目。
local StoryService = {}

---停止指定玩家当前正在播放的剧情，作为剧情正常结束处理。会触发剧情配表中配置的结束事件，并触发 OnStoryEnd 信号。用于剧情对话自然结束或需要主动结束的场景。
---**适用范围**: 客户端和服务端
---@param player Player 要停止剧情的玩家。服务端可指定任意玩家；客户端只能传入本地玩家。
---@param storyID String 要停止的剧情 ID。
function StoryService:EndStory(player, storyID) end

---跳过指定玩家当前正在播放的剧情。与 EndStory 的区别：本方法用于玩家主动跳过剧情（例如点击跳过按钮），不触发剧情配表中配置的结束事件。完成后触发 OnStorySkip 信号。
---**适用范围**: 客户端和服务端
---@param player Player 要跳过剧情的玩家。服务端可指定任意玩家；客户端只能传入本地玩家。
---@param storyID String 要跳过的剧情 ID。
function StoryService:SkipStory(player, storyID) end

---为指定玩家开始播放一个剧情对话，从该剧情的第一句对话开始播放。调用后玩家会进入剧情播放状态，并触发 OnStoryStart 信号。storyID 必须是地图剧情配表中存在的剧情 ID，否则不会播放。
---**适用范围**: 客户端和服务端
---@param player Player 要开始播放剧情的玩家。服务端可指定任意玩家；客户端只能传入本地玩家。
---@param storyID String 要开始播放的剧情 ID，对应地图剧情配表中的剧情条目。
function StoryService:StartStory(player, storyID) end

---TagService 标签管理器
---@class TagService : Unit
---@field TagAdded Signal<fun(tag: String)> 标签被首次添加。回调参数：tag 新增的标签
---@field TagRemoved Signal<fun(tag: String)> 标签被完全移除。回调参数：tag 移除的标签
local TagService = {}

---给组件{#0}添加标签{#1}
---@param unit SpaceUnit 组件
---@param tag String 标签
function TagService:AddTag(unit, tag) end

---获取所有的标签
---@return String[] 标签列表
function TagService:GetAllTags() end

---获取拥有标签{#0}的所有组件
---@param tag String 标签
---@return SpaceUnit[] 组件列表
function TagService:GetTagged(tag) end

---获取组件{#0}拥有的所有标签
---@param unit SpaceUnit 组件
---@return String[] 标签列表
function TagService:GetTags(unit) end

---判断组件{#0}是否拥有标签{#1}
---@param unit SpaceUnit 组件
---@param tag String 标签
---@return Bool 是否拥有标签
function TagService:HasTag(unit, tag) end

---从组件{#0}移除标签{#1}
---@param unit SpaceUnit 组件
---@param tag String 标签
function TagService:RemoveTag(unit, tag) end

---Task 服务，用于管理异步任务
---@class Task : Unit
local Task = {}

---取消一个任务协程
---@param coro thread 协程
---@return Bool 是否取消成功
function Task:Cancel(coro) end

---创建一个任务协程，并将其放入调度队列
---@param func function 任务
---@return thread 协程
function Task:Defer(func) end

---创建一个任务协程，并在指定的时间后恢复它
---@param duration Float 时长
---@param func function 任务
---@return thread 协程
function Task:Delay(duration, func) end

---创建一个任务协程，然后立即恢复它
---@param func function 任务
---@return thread 协程
function Task:Spawn(func) end

---等待指定的时间
---@param duration Float 时长
---@return Float 执行时过去的时间
function Task:Wait(duration) end

---TeleportService 地图传送服务
---**适用范围**: 仅服务端
---@class TeleportService : Unit
---@field TeleportInitFailed Signal<fun(player: Player, teleportResult: Enums.TeleportErrcode, errorMessage: String, mapId: String, teleportOptions: Table)> 传送初始化失败事件（服务端触发）。回调参数：player 传送的玩家, teleportResult 传送结果错误码, errorMessage 错误描述, mapId 本次传送的目标地图 mapId (传入 'SELF' 时, 事件上报的为解析后的当前地图实际 mapId), teleportOptions 传送选项 (含 ShouldReserveServer/ServerInstanceId 等字段)
local TeleportService = {}

---发起局内匹配, 匹配完成后返回可用于 TeleportAsync 的 ReservedServerAccessCode; 编辑器环境下返回 nil; 失败时抛出 error, 调用方应 pcall 保护。拿到的 accessCode 可填入 TeleportOptions.ReservedServerAccessCode, 再通过 TeleportAsync 把玩家送入匹配到的服务器。通过该途径获取的 accessCode 和 TeleportService:ReserveServerAsync 接口的返回值提供相同的效果
---**适用范围**: 仅服务端
---@param mapId String 匹配目标: 传 'SELF' 表示在当前地图发起局内匹配 (所有地图通用); 非多关卡地图仅支持 'SELF'; 多关卡地图可传关卡ID 在指定关卡匹配
---@param players Player[] 参与匹配的玩家列表（至少 1 个）
---@return String? 匹配结果中的 accessCode (编辑器环境返回 nil)
function TeleportService:ApplyIngameMatchAsync(mapId, players) end

---将单个玩家迁移到由匹配系统分配的另一服务器战斗实例; 编辑器环境下返回 false; 迁移成功返回 true, 失败返回 false。注意成功的情况下，执行顺序是先迁移玩家，再返回结果，因此收到回调的时候迁移已经完成了。组队中的玩家无法被迁移。
---**适用范围**: 仅服务端
---@param player Player 要迁移的玩家
---@return Bool 迁移结果 (编辑器环境返回 false)
function TeleportService:ChangeServerAsync(player) end

---创建传送选项实例
---**适用范围**: 仅服务端
---@return TeleportOptions 传送选项对象
function TeleportService:CreateTeleportOptions() end

---获取一个预留服务器的战场实例访问码, 返回 ReserveServerResult 对象; 编辑器环境下返回 nil; 失败时抛出 error, 调用方应 pcall 保护。ReserveServerResult.ReservedServerAccessCode 可填入 TeleportOptions, 再通过 TeleportAsync 把玩家送入预留的服务器战场实例。一但获取到访问码, 访问码始终可用, 如果该服务器战场实例当前不在运行, 会在传送开始时创建实例
---**适用范围**: 仅服务端
---@param mapId String 预留目标: 传 'SELF' 表示为当前地图预留其他服务器实例 (所有地图通用); 非多关卡地图仅支持 'SELF'; 多关卡地图可传关卡ID 为指定关卡预留
---@return ReserveServerResult? 保留服务器结果 (编辑器环境返回 nil)
function TeleportService:ReserveServerAsync(mapId) end

---将指定玩家迁移到目标地图, 编辑器环境下不会生效。未传 teleportOptions 时走 fire-and-forget 不返回; 传入时返回 TeleportAsyncResult。失败时抛出 error, 调用方应 pcall 保护
---**适用范围**: 仅服务端
---@param mapId String 传送目标: 传 'SELF' 表示传送到当前地图的其他服务器实例 (所有地图通用); 非多关卡地图仅支持 'SELF'; 多关卡地图可传关卡ID 传送到指定关卡
---@param players Player[] 待传送的玩家列表
---@param teleportOptions? TeleportOptions 传送选项, 可通过 TeleportService:CreateTeleportOptions() 创建 (可选)
---@return TeleportAsyncResult? 传送结果 (仅传入 teleportOptions 时返回; 未传时返回 nil)
function TeleportService:TeleportAsync(mapId, players, teleportOptions) end

---文字聊天服务，用于在游戏中管理玩家之间的文字聊天，支持官方频道与自定义频道，并可控制玩家进出频道、发送消息以及聊天界面的显隐。
---@class TextChatService : Unit
local TextChatService = {}

---添加自定义聊天频道
---@param channelName String 频道名称
function TextChatService:AddCustomTextChannel(channelName) end

---玩家进入文本聊天频道
---@param player Player 玩家
---@param channelName String 频道名称
function TextChatService:EnterTextChannel(player, channelName) end

---获取文本聊天频道信息列表
---@return any[] 频道信息列表，每项包含 name 字段
function TextChatService:GetTextChannelInfo() end

---玩家离开文本聊天频道
---@param player Player 玩家
---@param channelName String 频道名称
function TextChatService:LeaveTextChannel(player, channelName) end

---移除自定义聊天频道
---@param channelName String 频道名称
function TextChatService:RemoveCustomTextChannel(channelName) end

---发送聊天消息
---@param player Player 玩家
---@param channelName String 频道名称
---@param message String 消息内容
function TextChatService:SendMessage(player, channelName, message) end

---设置聊天按钮可见性
---@param visible Bool 是否可见
function TextChatService:SetChatButtonVisible(visible) end

---设置官方聊天频道可见性
---@param channelName String 频道名称
---@param visible Bool 是否可见
function TextChatService:SetOfficialTextChannelVisible(channelName, visible) end

---TimerService 用于管理游戏计时器
---@class TimerService : Unit
local TimerService = {}

---创建一个计时器
---@param repeatCount Int 重复次数，-1表示无限次
---@param interval Float 时间间隔
---@param execute Bool 是否立即执行
---@param func function 回调函数
---@return Timer 计时器对象
function TimerService:CreateTimer(repeatCount, interval, execute, func) end

---TweenService 补间动画服务
---@class TweenService : Unit
local TweenService = {}

---创建 Tween 对象
---@param instance Unit 目标对象
---@param tweenInfo TweenInfo TweenInfo 配置
---@param goalTable Table 目标属性表
---@return Tween Tween 对象
function TweenService:Create(instance, tweenInfo, goalTable) end

---UserInputService 用于检测和处理各种类型的用户输入
---**适用范围**: 仅客户端
---@class UserInputService
---@field ClickEggyJump Signal<fun()>
---@field ClickEggyLift Signal<fun()>
---@field ClickEggyRoll Signal<fun()>
---@field ClickEggyRush Signal<fun()>
---@field InputBegan Signal<fun(inputObject: InputObject, gameProcessedEvent: Bool)> 回调参数：inputObject 输入对象, gameProcessedEvent 游戏是否已处理该事件
---@field InputChanged Signal<fun(inputObject: InputObject, gameProcessedEvent: Bool)> 回调参数：inputObject 输入对象, gameProcessedEvent 游戏是否已处理该事件
---@field InputEnded Signal<fun(inputObject: InputObject, gameProcessedEvent: Bool)> 回调参数：inputObject 输入对象, gameProcessedEvent 游戏是否已处理该事件
---@field JoystickEnd Signal<fun()>
---@field JoystickMove Signal<fun(x: Float, y: Float, length: Float)> 回调参数：x x轴值, y y轴值, length 摇杆偏移长度
---@field JoystickStart Signal<fun()>
---@field LastInputTypeChanged Signal<fun(lastInputType: Enums.UserInputType)> 回调参数：lastInputType 最后的输入类型
---@field TouchEnded Signal<fun(touch: InputObject, gameProcessedEvent: Bool)> 回调参数：touch 触摸输入对象, gameProcessedEvent 游戏是否已处理该事件
---@field TouchMoved Signal<fun(touch: InputObject, gameProcessedEvent: Bool)> 回调参数：touch 触摸输入对象, gameProcessedEvent 游戏是否已处理该事件
---@field TouchPinch Signal<fun(touchPositions: Table<Vector2>, scale: Float, velocity: Float, state: Enums.UserInputState, gameProcessedEvent: Bool)> 回调参数：touchPositions 两根手指当前屏幕坐标, scale 当前距离/初始距离，1.0=未变化, velocity scale 的瞬时变化率（per 秒）, state 手势状态：Begin/Change/End/Cancel, gameProcessedEvent 游戏是否已处理该事件
---@field TouchRotate Signal<fun(touchPositions: Table<Vector2>, rotation: Float, velocity: Float, state: Enums.UserInputState, gameProcessedEvent: Bool)> 回调参数：touchPositions 两根手指当前屏幕坐标, rotation 相对初始角度的累计弧度（带符号，逆时针正）, velocity rotation 的瞬时变化率（rad/秒）, state 手势状态：Begin/Change/End/Cancel, gameProcessedEvent 游戏是否已处理该事件
---@field TouchStarted Signal<fun(touch: InputObject, gameProcessedEvent: Bool)> 回调参数：touch 触摸输入对象, gameProcessedEvent 游戏是否已处理该事件
---@field TouchTap Signal<fun(touchPositions: Table<Vector2>, gameProcessedEvent: Bool)> 回调参数：touchPositions 参与手势的所有手指屏幕坐标（Tap 永远是 1 个）, gameProcessedEvent 游戏是否已处理该事件
local UserInputService = {}

---屏幕(设备)坐标转UI(cocos)坐标
---**适用范围**: 仅客户端
---@param screenPos Vector2 屏幕(设备)坐标：左上原点、真实像素，与 GetMouseLocation 一致
---@return Vector2 UI(cocos)坐标：左下原点、设计分辨率，与 EUINode:GetWorldPosition 一致
function UserInputService:ConvertScreenToUIPosition(screenPos) end

---UI(cocos)坐标转屏幕(设备)坐标
---**适用范围**: 仅客户端
---@param uiPos Vector2 UI(cocos)坐标：左下原点、设计分辨率，与 EUINode:GetWorldPosition 一致
---@return Vector2 屏幕(设备)坐标：左上原点、真实像素，与 GetMouseLocation 一致
function UserInputService:ConvertUIToScreenPosition(uiPos) end

---获取当前摇杆偏移长度
---**适用范围**: 仅客户端
---@return Float 0.0
function UserInputService:GetJoystickMoveLength() end

---获取当前摇杆移动方向向量
---**适用范围**: 仅客户端
---@return Vector2 (0， 0)
function UserInputService:GetJoystickMoveVector() end

---获取所有当前正在被按下的键盘按键的 InputObject 列表
---**适用范围**: 仅客户端
---@return InputObject[] 按下的键对应的 InputObject 数组（顺序无保证）
function UserInputService:GetKeysPressed() end

---获取最后输入类型
---**适用范围**: 仅客户端
---@return Enums.UserInputType 最后输入类型
function UserInputService:GetLastInputType() end

---获取鼠标行为模式
---**适用范围**: 仅客户端
---@return Enums.MouseBehavior 鼠标行为
function UserInputService:GetMouseBehavior() end

---获取所有当前正在被按下的鼠标按键的 InputObject 列表
---**适用范围**: 仅客户端
---@return InputObject[] 按下的鼠标按键对应的 InputObject 数组（顺序无保证）
function UserInputService:GetMouseButtonsPressed() end

---获取当前帧累计的鼠标位移
---**适用范围**: 仅客户端
---@return Vector2 当前帧鼠标位移；未锁定时为 (0， 0)
function UserInputService:GetMouseDelta() end

---获取鼠标灵敏度
---**适用范围**: 仅客户端
---@return Float 鼠标灵敏度
function UserInputService:GetMouseDeltaSensitivity() end

---获取鼠标图标是否启用
---**适用范围**: 仅客户端
---@return Bool 是否启用鼠标图标
function UserInputService:GetMouseIconEnabled() end

---获取鼠标位置
---**适用范围**: 仅客户端
---@return Vector2 鼠标位置
function UserInputService:GetMouseLocation() end

---获取输入类型的描述
---**适用范围**: 仅客户端
---@param inputType Enums.UserInputType 输入类型
---@return String 名字描述
function UserInputService:GetStringForInputType(inputType) end

---返回 KeyCode 对应的可输入字符（QWERTY 布局）
---**适用范围**: 仅客户端
---@param keyCode Enums.KeyCode KeyCode 整数值（直接传 KeyCode.W 等枚举即可）
---@return String 可输入字符或空字符串，永不返回 nil
function UserInputService:GetStringForKeyCode(keyCode) end

---检查某个按键是否正在被按下
---**适用范围**: 仅客户端
---@param keyCode Enums.KeyCode 键盘按键代码
---@return Bool 是否正在被按下
function UserInputService:IsKeyDown(keyCode) end

---检查某个鼠标按钮是否正在被按下
---**适用范围**: 仅客户端
---@param userInputType Enums.UserInputType 用户输入类型
---@return Bool 是否正在被按下
function UserInputService:IsMouseButtonPressed(userInputType) end

---设置鼠标行为模式
---**适用范围**: 仅客户端
---@param behavior Enums.MouseBehavior 鼠标行为 (Default=0, LockCenter=1, LockCurrentPosition=2)
function UserInputService:SetMouseBehavior(behavior) end

---设置鼠标灵敏度
---**适用范围**: 仅客户端
---@param sensitivity Float 鼠标灵敏度
function UserInputService:SetMouseDeltaSensitivity(sensitivity) end

---设置鼠标图标是否启用
---**适用范围**: 仅客户端
---@param enabled Bool 是否启用鼠标图标
function UserInputService:SetMouseIconEnabled(enabled) end

---设置触屏移动模式
---**适用范围**: 仅客户端
---@param mode Int 触屏移动模式 (0=UserChoice, 1=Thumbstick, 2=FixedThumbstick, 3=DynamicThumbstick, 4=Scriptable)
function UserInputService:SetTouchMovementMode(mode) end

---检查是否支持触摸输入
---**适用范围**: 仅客户端
---@return Bool 是否支持触摸
function UserInputService:TouchEnabled() end

---VibrationService 设备震动服务
---**适用范围**: 客户端和服务端
---@class VibrationService : Unit
local VibrationService = {}

---开始手机震动
---**适用范围**: 客户端和服务端
---@param player Player 玩家
---@param vibrateType Int 震动模式
---@param vibrateCount Int 震动次数
---@param vibrateInterval Float 震动间隔
function VibrationService:StartVibration(player, vibrateType, vibrateCount, vibrateInterval) end

---World的核心职责是容纳存在于3D世界中的所有对象，主要是各类Unit如 WorldUnit、ModelUnit、EffectUnit 等）。当这些对象作为World的后代时，它们将处于活跃状态。对于具有物理属性的Unit（如 WorldUnit），这意味着它们将被渲染，并与其他Unit及世界进行物理交互。脱离World层级的对象不会被渲染也不会参与物理计算，直至被重新挂载到World树中。
---@class World : WorldRoot
---@field AOIDestroyType Int AOI销毁类型
---@field AOIType Int AOI类型
---@field AOIType2MaxRadius Float AOI外圈
---@field AOIType2MinRadius Float AOI内圈
---@field AOIType2StreamingMainRadius Float Streaming主半径
---@field CurrentCamera CameraUnit 当前相机
---@field StreamingMainRadius Float Streaming主半径
local World = {}

---加载Asset
---@param assetId String 资产预设ID
---@return Unit[] Units
function World:CreateAsset(assetId) end

---在当前 World 下创建一个新的单位实例。本方法实质是 game:CreateUnit 的语法糖：内部直接调用 game:CreateUnit(unitType, values) 完成真正的创建逻辑，并在此基础上额外做：是当 values 未指定 Parent 时自动将新单位挂载到当前 World 下。
---@param unitType String 要创建的单位类型名称，如 "WorldUnit"、"ModelUnit"、"EffectUnit" 等
---@param values? Table 初始化属性键值表。可填写的属性键来自对应 unitType 的 API 文档（即该类型及其继承链上声明的属性），例如 { Name = "box", Position = Vector3.new(0, 10, 0), Parent = world }；省略 Parent 时默认挂载到当前 World。具体支持哪些属性以该单位类型 API 文档中列出的属性为准。
---@return Unit 新创建的单位实例
function World:CreateUnit(unitType, values) end

---获取全局自定义事件信号
---@param eventName String 自定义事件名
---@return Signal 自定义事件信号
function World:GetCustomEventSignal(eventName) end

---获取服务器时间
---@return Float 服务器时间，单位为秒
function World:GetServerTime() end

--========================== 单位 Unit ==========================

---环境光遮蔽效果
---**适用范围**: 客户端和服务端
---@class AmbientOcclusionEffect : BasePostEffect
---@field Bias Float 深度偏移
---@field Intensity Float 遮蔽强度
---@field Radius Float 采样半径
local AmbientOcclusionEffect = {}

---旋转运动器
---@class AngularMotorUnit : BaseMotorUnit
---@field AngularVelocity Vector3 角速度
local AngularMotorUnit = {}

---可播放动画的组件
---@class AnimatedUnit : WorldUnit
local AnimatedUnit = {}

---获取当前动画播放状态
---@return Table 动画状态 { animName， startTime， looped， speed， isPlaying， playToken， serverTime }
function AnimatedUnit:GetAnimationState() end

---播放模型动画（服务端调用=权威播放并同步所有客户端；客户端调用=仅本端播放，不同步；需多端同步时请从服务端调用）
---@param animName String 模型内包含的动画名称或单独上传的动画资源 ID（需与模型骨骼匹配）
---@param params? Table 播放参数 { startTime, looped, speed }
function AnimatedUnit:PlayAnimation(animName, params) end

---停止当前模型动画（服务端调用=权威停止并同步所有客户端；客户端调用=仅本端停止，不同步）
function AnimatedUnit:StopAnimation() end

---AnimationTrack 动画轨道对象
---**适用范围**: 客户端和服务端
---@class AnimationTrack : Unit
---@field Animation Animation 动画资源引用对象（只读），包含 Name（短名）和 AnimationId（asset URI）属性
---@field FilterType Enums.AnimationFilterType 骨骼过滤类型，参见 AnimationFilterType 枚举
---@field IsPlaying Bool 是否正在播放（只读）
---@field Length Float 动画长度，单位秒（只读）
---@field Looped Bool 是否循环播放
---@field Parent Animator 所属的 Animator
---@field Priority Enums.AnimationPriority 播放优先级，参见 AnimationPriority 枚举
---@field Speed Float 播放速度，1.0 为正常速度，0 为暂停
---@field TimePosition Float 当前播放位置，单位秒
---@field WeightCurrent Float 当前权重（只读），在渐变过程中会从旧值过渡到 WeightTarget
---@field WeightTarget Float 目标权重，0~1 之间
---@field DidLoop Signal<fun()>
---@field Ended Signal<fun()>
---@field Stopped Signal<fun()>
local AnimationTrack = {}

---在动画时间轴上添加一个 Cue 标记点
---当动画播放到该时间点时会触发对应的信号
---**适用范围**: 客户端和服务端
---**示例**:
---```lua
---track:AddCue("hit", 0.5)
---track:GetCueReachedSignal("hit"):Connect(function()
---    print("Hit cue reached!")
---end)
---```
---@param cueName String Cue 名称，非空字符串
---@param timePosition Float Cue 触发的时间位置（秒），非负数
function AnimationTrack:AddCue(cueName, timePosition) end

---调整动画播放速度
---设为 0 可暂停动画，恢复非零值可继续播放
---**适用范围**: 客户端和服务端
---**示例**:
---```lua
---track:AdjustSpeed(2.0)  -- 两倍速
---track:AdjustSpeed(0)    -- 暂停
---```
---@param speed Float 新的播放速度，默认 1
function AnimationTrack:AdjustSpeed(speed) end

---调整动画混合权重
---权重会从当前值在 fadeTime 时间内渐变到目标值
---**适用范围**: 客户端和服务端
---**示例**:
---```lua
---track:AdjustWeight(0.5, 0.5)  -- 在 0.5 秒内渐变到 50% 权重
---```
---@param weight Float 目标权重，默认 1
---@param fadeTime Float 渐变时间（秒），默认 0.1
function AnimationTrack:AdjustWeight(weight, fadeTime) end

---获取指定 Cue 的信号对象，动画播放到该 Cue 时触发
---**适用范围**: 客户端和服务端
---@param name String Cue 名称
---@return Signal 可用于 Connect 的信号对象
function AnimationTrack:GetCueReachedSignal(name) end

---获取指定 Marker 的信号对象（GetCueReachedSignal 的别名）
---**适用范围**: 客户端和服务端
---@param name String Marker 名称
---@return Signal 可用于 Connect 的信号对象
function AnimationTrack:GetMarkerReachedSignal(name) end

---获取指定 Cue 的时间位置
---**适用范围**: 客户端和服务端
---@param name String Cue 名称
---@return Float Cue 的时间位置（秒），不存在则返回 nil
function AnimationTrack:GetTimeOfCue(name) end

---获取指定 Keyframe 的时间位置（GetTimeOfCue 的别名）
---**适用范围**: 客户端和服务端
---@param name String Keyframe 名称
---@return Float 时间位置（秒），不存在则返回 nil
function AnimationTrack:GetTimeOfKeyframe(name) end

---播放动画
---若动画尚未加载完成（Length == 0），等待加载完成后自动播放
---客户端：当主体是玩家或 NetworkOwner 是玩家时，播放会自动同步到其他客户端
---服务端：播放始终同步到所有客户端
---**适用范围**: 客户端和服务端
---**示例**:
---```lua
---local track = animator:LoadAnimation(ASSET_ID)
---track:Play(0.2, 1, 1.5)
---```
---@param fadeTime Float 淡入时间（秒），默认 0.1
---@param weight Float 目标混合权重，默认 1
---@param speed Float 播放速度，默认 1，不支持负数（会被置为 1）
function AnimationTrack:Play(fadeTime, weight, speed) end

---移除指定名称的所有 Cue 标记点
---**适用范围**: 客户端和服务端
---@param cueName String 要移除的 Cue 名称
function AnimationTrack:RemoveCue(cueName) end

---停止动画播放
---**适用范围**: 客户端和服务端
---**示例**:
---```lua
---track:Stop(0.2)
---```
---@param fadeTime Float 淡出时间（秒），默认 0.1
function AnimationTrack:Stop(fadeTime) end

---动画控制器
---**适用范围**: 客户端和服务端
---@class Animator : Unit
---@field Parent Unit 被驱动的父 Unit（拥有骨骼、动画组件等）
---@field AnimationPlayed Signal<fun(animationTrack: AnimationTrack)> 回调参数：animationTrack 开始播放的动画轨道
local Animator = {}

---获取当前所有正在播放的动画轨道
---**适用范围**: 客户端和服务端
---@return AnimationTrack[] AnimationTrack 数组
function Animator:GetPlayingAnimationTracks() end

---加载动画轨道，返回可播放的 AnimationTrack
---同一个 contentId 多次调用会返回缓存的同一个 AnimationTrack 实例
---支持传入 Animation 对象或 asset URI 字符串
---**适用范围**: 客户端和服务端
---**示例**:
---```lua
---local track = animator:LoadAnimation("official://animation/XX")
---local anim = Animation.New("walk", "official://animation/XX")
---local track2 = animator:LoadAnimation(anim)
---```
---@param contentId String|Animation asset URI（如 official://animation/XX），或 Animation 对象
---@return AnimationTrack 动画轨道对象
function Animator:LoadAnimation(contentId) end

---Attachment 表示依附于 Parent 的局部坐标锚点，可通过局部 Position、Rotation 或虚拟的世界空间属性读写变换。世界空间属性会根据 Parent 的世界变换与局部变换互相换算。
---**适用范围**: 客户端和服务端
---@class Attachment : Unit
---@field Axis Vector3 运行时只读虚拟属性，返回 Attachment 世界旋转作用在本地 X 轴后的方向。getter 返回新的 Vector3 值，修改该返回值本身不会影响原 Attachment。
---@field CFrame CFrame 运行时虚拟属性，由局部 Position 和 Rotation 组成；写入时会同时更新 Position 与 Rotation。getter 返回新的 CFrame 值，修改该返回值本身不会影响原 Attachment；需要重新赋值给 CFrame 才会生效。
---@field Orientation Quaternion Rotation 的别名，读写都会映射到局部 Rotation。读取 Quaternion 后修改该返回值本身不会影响原 Attachment；需要重新赋值给 Orientation 或 Rotation 才会生效。
---@field Position Vector3 Attachment 相对 Parent 的局部位置。读取 Vector3 后修改该返回值本身不会影响原 Attachment；需要重新赋值给 Position 才会生效。
---@field Rotation Quaternion Attachment 相对 Parent 的局部旋转。Orientation 是该属性的别名。读取 Quaternion 后修改该返回值本身不会影响原 Attachment；需要重新赋值给 Rotation 才会生效。
---@field SecondaryAxis Vector3 运行时只读虚拟属性，返回 Attachment 世界旋转作用在本地 Y 轴后的方向。getter 返回新的 Vector3 值，修改该返回值本身不会影响原 Attachment。
---@field Visible Bool 控制编辑器或调试显示中该 Attachment 锚点是否可见。
---@field WorldCFrame CFrame 运行时虚拟属性，由 WorldPosition 和 WorldRotation 组成；写入时会根据 Parent 的世界变换换算并更新局部 Position 与 Rotation。getter 返回新的 CFrame 值，修改该返回值本身不会影响原 Attachment；需要重新赋值给 WorldCFrame 才会生效。
---@field WorldPosition Vector3 运行时虚拟属性，读写时会根据 Parent 的世界变换与局部 Position 互相换算；不作为底层同步字段复制。读取 Vector3 后修改该返回值本身不会影响原 Attachment；需要重新赋值给 WorldPosition 才会生效。
---@field WorldRotation Quaternion 运行时虚拟属性，读写时会根据 Parent 的世界变换与局部 Rotation 互相换算；不作为底层同步字段复制。读取 Quaternion 后修改该返回值本身不会影响原 Attachment；需要重新赋值给 WorldRotation 才会生效。
local Attachment = {}

---获取引用当前 Attachment 的约束单位列表。返回的是列表副本，修改该列表不会影响原 Attachment 或约束关系。
---**适用范围**: 客户端和服务端
---@return Unit[] 引用当前 Attachment 的约束单位数组副本。
function Attachment:GetConstraints() end

---背包单位，运行时容器，管理玩家携带的所有物品。
---@class Backpack : Unit
local Backpack = {}

---物品基类，所有可放入背包的物品的基类，提供图标等基础属性。
---@class BackpackItem : Unit
---@field Icon String 图标
local BackpackItem = {}

---球窝约束用于在两个物理部件之间创建类似球关节的连接，允许绕连接点自由旋转。通过设置摆动角和扭转角限制，可以精确控制旋转范围。使用时需设置 Attachment0 和 Attachment1 指向两个已存在的 Attachment。物理约束建议在服务端创建。
---@class BallSocketConstraint : Unit
---@field Active Bool 当前是否激活
---@field Attachment0 Attachment Attachment0
---@field Attachment1 Attachment Attachment1
---@field Enabled Bool 启用约束
---@field LimitsEnabled Bool 启用摆动角限制
---@field MaxFrictionTorque Float 最大摩擦扭矩(当前仅存储)
---@field Radius Float 可视化半径
---@field Restitution Float 弹性(0-1)
---@field TwistLimitsEnabled Bool 启用扭转角限制
---@field TwistLowerAngle Float 最小扭转角(度)
---@field TwistUpperAngle Float 最大扭转角(度)
---@field UpperAngle Float 最大摆动角(度)
local BallSocketConstraint = {}

---生物角色控制器基类，承载生命体的状态、生命值、移动与跳跃、血条与名字显示等通用能力。通过Unit.Controller获取使用。不同Unit会有不同的Controller实现，如EggyController，HumanController，提供各自特有的能力与表现。
---@class BaseController : Unit
---@field AutoRotate Bool 自动朝向移动方向
---@field DisplayDistanceType Int 显示距离类型
---@field GravityEnabled Bool 受重力作用
---@field HPBarShowMode Int 血条显示模式
---@field Health Float 生命值
---@field HealthDisplayDistance Float 血条显示距离
---@field JumpPower Float 跳跃垂直速度
---@field MaxHealth Float 最大生命值
---@field MaxMultiJumpCount Int 多段跳次数
---@field MultiJumpCooldown Float 多段跳冷却
---@field NameDisplayDistance Float 名字显示距离
---@field WalkSpeed Float 移动速度
---@field Died Signal<fun()> 死亡时触发
---@field ExtraStatesChanged Signal<fun(old: String[], new: String[])> 附加状态列表发生变化时触发。回调参数：old 旧附加状态列表, new 新附加状态列表
---@field HealthChanged Signal<fun(health: Float)> 生命值变化时触发。回调参数：health 当前生命值
---@field MoveToFinished Signal<fun(isReached: Bool)> MoveTo 移动结束时触发。回调参数：isReached 是否到达目的地
---@field OnCollisionEnter Signal<fun(other: Unit, info: Table)> 发生碰撞进入时触发。回调参数：other 碰撞的对方对象, info 碰撞信息，包含point和normal
---@field OnCollisionExit Signal<fun(other: Unit)> 结束碰撞时触发。回调参数：other 碰撞的对方对象
---@field OnJump Signal<fun(unit: SpaceUnit)> 起跳时触发。回调参数：unit 触发的生物
---@field OnLanded Signal<fun()> 落地时触发，仅客户端生效
---@field OnReborn Signal<fun(unit: SpaceUnit)> 复活时触发。回调参数：unit 触发的生物
---@field OnStartFalling Signal<fun()> 开始下落时触发，仅客户端生效
---@field StateChanged Signal<fun(old: Enums.ControllerStateType, new: Enums.ControllerStateType)> 状态发生变化时触发。回调参数：old 旧状态, new 新状态
local BaseController = {}

---添加一个附加状态
---@param stateName String 附加状态名
---@return Bool 是否添加成功
function BaseController:AddExtraState(stateName) end

---对当前角色施加世界坐标系方向的力，如controller:ApplyForce(math.Vector3(0, 1000, 0))
---@param force Vector3 施加的力
function BaseController:ApplyForce(force) end

---切换到指定角色状态
---@param state Enums.ControllerStateType 目标状态
function BaseController:ChangeState(state) end

---获取当前所有附加状态
---@return String[] 附加状态名列表
function BaseController:GetExtraStates() end

---获取脚下所踩的对象
---@return SpaceUnit 脚下所踩Unit
function BaseController:GetFloor() end

---获取当前角色状态
---@return Enums.ControllerStateType 当前状态类型
function BaseController:GetState() end

---查询指定状态是否启用
---@param state Enums.ControllerStateType 指定状态
---@return Bool 该状态是否已启用
function BaseController:GetStateEnabled(state) end

---治疗生命值
---@param health Float 治疗数值
function BaseController:Heal(health) end

---是否处于地面站立状态
---@return Bool 是否地面站立
function BaseController:IsGrounded() end

---执行一次跳跃
function BaseController:Jump() end

---按方向持续移动
---@param moveDirection Vector3 移动方向
---@param relativeToCamera Bool 是否相对于相机
function BaseController:Move(moveDirection, relativeToCamera) end

---移动到指定位置或目标对象
---@param position Vector3 目标位置
---@param targetUnit Unit 目标模型(可选)
function BaseController:MoveTo(position, targetUnit) end

---复活角色
function BaseController:Reborn() end

---注册自定义角色状态及其进入与离开回调
---@param stateName String 状态名称
---@param onPreEnter function 预进入回调
---@param onEnter function 进入回调
---@param onPreLeave function 预离开回调
---@param onLeave function 离开回调
---@return Bool 是否注册成功
function BaseController:RegisterCustomState(stateName, onPreEnter, onEnter, onPreLeave, onLeave) end

---注册自定义附加状态及其进入与离开回调
---@param stateName String 状态名称
---@param onPreEnter function 预进入回调
---@param onEnter function 进入回调
---@param onPreLeave function 预离开回调
---@param onLeave function 离开回调
---@return Bool 是否注册成功
function BaseController:RegisterExtraState(stateName, onPreEnter, onEnter, onPreLeave, onLeave) end

---移除指定的附加状态
---@param stateName String 附加状态名
---@return Bool 是否删除成功
function BaseController:RemoveExtraState(stateName) end

---设置最大线速度
---@param velocity Float 最大线速度
function BaseController:SetMaxLinearVelocity(velocity) end

---设置物理开关
---@param active Bool 物理开关
function BaseController:SetPhysicsActive(active) end

---启用或禁用指定状态
---@param state Enums.ControllerStateType 指定状态
---@param enabled Bool 是否启用
function BaseController:SetStateEnabled(state, enabled) end

---造成伤害
---@param damage Float 伤害数值
function BaseController:TakeDamage(damage) end

---取消注册自定义角色状态
---@param stateName String 状态名称
---@return Bool 是否取消注册成功
function BaseController:UnRegisterCustomState(stateName) end

---取消注册自定义附加状态
---@param stateName String 状态名称
---@return Bool 是否取消注册成功
function BaseController:UnRegisterExtraState(stateName) end

---运动器基类
---@class BaseMotorUnit : Unit
---@field ActiveEventName String 运动开始事件
---@field ArrivalPauseTime Float 到达后暂停时间
---@field BackPauseTime Float 返程后暂停时间
---@field BackTracking Bool 开启返程
---@field Duration Float 运动持续时间
---@field HalfCycleTime Float 单程运动时间
---@field InitDelayTime Float 初始延迟时间
---@field IsActive Bool 是否启用
---@field IsCycle Bool 是否循环
---@field StopEventName String 运动结束事件
---@field OnMotorStart Signal<fun()>
---@field OnMotorStop Signal<fun()>
local BaseMotorUnit = {}

function BaseMotorUnit:Backtrack() end

function BaseMotorUnit:Pause() end

function BaseMotorUnit:Resume() end

function BaseMotorUnit:Start() end

function BaseMotorUnit:Stop() end

---BasePart是具有物理碰撞和渲染表现的3D组件基类，继承自SpaceUnit。提供坐标变换、碰撞检测、物理模拟、渲染控制和力学操作等核心能力。不可直接创建，由WorldUnit、RenderUnit等子类继承使用。
---@class BasePart : SpaceUnit
---@field AssemblyAngularVelocity Vector3 所属装配体的整体角速度（只读）
---@field AssemblyCenterOfMass Vector3 所属装配体的质心世界坐标（只读）
---@field AssemblyLinearVelocity Vector3 所属装配体的整体线速度（只读）
---@field AssemblyMass Float 所属装配体的总质量（只读）
---@field AssemblyRootPriority Int 在装配体中作为根节点的优先级，数值越大越优先成为装配体根
---@field CFrame CFrame 组件在世界空间中的完整坐标变换，包含位置和旋转
---@field CastShadow Bool 控制模型是否向场景投射阴影
---@field CustomAppearanceId String 自定义外观的资源ID，启用自定义外观后生效
---@field ModelAlpha Float 控制模型的整体透明度，0 为完全透明，1 为完全不透明
---@field ModelColor1 Color 模型染色区域1的颜色；启用自定义外观后该属性不生效
---@field ModelColor2 Color 模型染色区域2的颜色；启用自定义外观后该属性不生效
---@field ModelColor3 Color 模型染色区域3的颜色；启用自定义外观后该属性不生效
---@field ModelColor4 Color 模型染色区域4的颜色；启用自定义外观后该属性不生效
---@field ModelVisible Bool 控制模型是否可见，隐藏后仍参与物理碰撞
---@field OcclusionType Int 当模型遮挡住摄像机与玩家之间的视线时的处理策略
---@field Persistent Bool 仅在World开启了AOI功能时此字段生效
---@field PivotOffset CFrame 轴心点相对于组件原点的偏移，影响 GetPivot 和 PivotTo 的结果
---@field Position Vector3 单位在世界空间中的位置坐标。该属性为 CFrame 的语法糖：读取等价于 CFrame.Position，写入会保持当前旋转不变、仅重建 CFrame 的位置分量
---@field Rotation Quaternion 单位在世界空间中的旋转，以四元数表示。该属性为 CFrame 的语法糖：读取等价于 CFrame.Rotation，写入会保持当前位置不变、仅重建 CFrame 的旋转分量
---@field Scale Vector3 组件各轴的缩放比例，默认为 (1, 1, 1)
---@field Size Vector3 渲染层尺寸，等于 Scale × ModelBaseSize。无模型时为 nil。修改Scale或模型可改变渲染尺寸
---@field SkinId String 模型使用的皮肤资源ID，用于切换模型外观；启用自定义外观后该属性不生效
---@field UseCustomAppearance Bool 启用后使用自定义外观替代默认模型渲染
local BasePart = {}

---获取通过焊接等约束与此物体相连的所有单位
---@return Table
function BasePart:GetConnectedUnits() end

---获取当前负责该物体物理模拟的玩家
---@return Player
function BasePart:GetNetworkOwner() end

---返回该物体的物理拥有者是否由引擎自动决定。返回 true 表示引擎会在玩家感知/接触时自动分配所有权；返回 false 表示已被手动固定（SetNetworkOwner 会隐式切为手动）
---@return Bool
function BasePart:GetNetworkOwnershipAuto() end

---判断当前是否为该物体的物理模拟拥有者
---@return Bool
function BasePart:IsNetworkOwnerSide() end

---判断物体是否为焊接约束中的子节点
---@return Bool
function BasePart:IsWeldConstraintChild() end

---判断物体是否为焊接约束中的根节点
---@return Bool
function BasePart:IsWeldConstraintRoot() end

---将物体的物理模拟权限转移给指定玩家
---@param player Player 要转移权限的玩家对象
function BasePart:SetNetworkOwner(player) end

---设置物体的物理拥有者是否由引擎自动分配。传 true（缺省）恢复引擎自动分配，用于撤销 SetNetworkOwner 的手动固定；传 false 则锁定为手动。仅服务端调用生效，恢复自动后重新分配在下一次选择器求值时发生
---@param isAuto? Bool true 为恢复引擎自动分配（缺省），false 为锁定为手动
function BasePart:SetNetworkOwnershipAuto(isAuto) end

---将本地渲染位置强制同步到最新的物理模拟位置，消除渲染延迟
function BasePart:SyncRenderToPhysics() end

---后处理基类
---**适用范围**: 客户端和服务端
---@class BasePostEffect : Unit
---@field Enabled Bool 启用
local BasePostEffect = {}

---脚本基类
---@class BaseScript : Unit
---@field IsEnabled Bool 启用
---@field SourceCode String 代码
local BaseScript = {}

---天空基类
---**适用范围**: 客户端和服务端
---@class BaseSky : Unit
---@field AffectedByFog Bool 受雾影响
local BaseSky = {}

---本地事件对象: 纯逻辑容器，提供 Event 信号（Connect/Once/Wait）与 Fire 变参触发，无渲染/物理表现。
---@class BindableEvent : Unit
---@field Event Signal 本地事件信号，支持 Connect/Once/Wait 监听；调用 BindableEvent:Fire 时，所有监听函数收到转发的参数。
local BindableEvent = {}

---监听事件信号，事件触发时调用监听函数；返回的连接句柄可用于断开监听。
---@param func function 事件触发时调用的监听函数
---@return Connection 可用于断开监听的连接句柄
function BindableEvent:Connect(func) end

---触发事件，向所有监听函数转发本次调用传入的参数（变参）。
---@param args? Any 事件参数
function BindableEvent:Fire(args) end

---监听事件信号，仅在第一次事件触发时调用监听函数后自动断开。
---@param func function 第一次事件触发时调用的监听函数
---@return Connection 可用于提前断开监听的连接句柄
function BindableEvent:Once(func) end

---在协程中挂起，直到事件触发后恢复并返回事件参数；可选超时（超时返回 false, "Timed out"）。
---@param duration? number 超时时间（秒）
---@return Any 事件参数
function BindableEvent:Wait(duration) end

---泛光效果
---**适用范围**: 客户端和服务端
---@class BloomEffect : BasePostEffect
---@field Intensity Float 强度
---@field LuminanceScale Float 亮度缩放
---@field Size Float 扩散范围
---@field Threshold Float 亮度阈值
local BloomEffect = {}

---相机控制
---**适用范围**: 客户端和服务端
---@class CameraUnit : SpaceUnit
---@field CFrame CFrame 相机坐标矩阵（Position + Rotation 的组合）
---@field CameraType Enums.CameraType 相机类型（自动映射到 Mode）
---@field ClippingRange Vector2 相机裁剪平面范围，默认为[0.5, 15000]（X=近裁剪面, Y=远裁剪面）
---@field DevCameraOcclusionMode Enums.DevCameraOcclusionMode 相机遮挡处理模式: 0=Zoom(推镜头), 1=Invisicam(目标半透明), 2=EggyHybrid(两者)
---@field Distance Float 与跟随目标之间的相机距离
---@field ExtraSubject Unit 相机额外的关注目标, 默认为空, 非空时预设行为下相机的朝向状态会参考此目标
---@field FieldOfView Float 相机垂直视场角
---@field FieldOfViewMode Int 视场角模式: 0=Vertical(默认), 1=Diagonal, 2=MaxAxis
---@field Focus Vector3 相机聚焦点，用于确定相机朝向
---@field IsActive Bool 相机是否处于激活状态
---@field Mode Enums.CameraMode 相机行为模式（Eggy 原生模式）
---@field NearPlaneZ Float 近裁剪平面距离
---@field Pitch Float 相机俯仰角(degree), 改变视角的上下角度, 参考世界上方向
---@field Position Vector3 相机当前位置, 预设行为下会按参照更新此状态
---@field Priority Float 相机展示优先级，全局最高展示优先级的相机会操作实际的渲染相机
---@field ProjectionType Enums.CameraProjection 相机投影模式
---@field Roll Float 相机滚转角(degree), 沿前后方向旋转, 倾斜画面
---@field Rotation Quaternion 相机当前朝向, 预设行为下会按参照更新此状态
---@field ScriptableBehaviour Table 相机脚本行为
---@field TrackingUnit Unit 标记当前相机跟随目标, 供行为参考
---@field ViewportSize Vector2 视口尺寸（像素）
---@field Yaw Float 相机偏航角(degree), 改变视角的左右方向
---@field AfterUpdateState Signal<fun(delta: Float)> 回调参数：delta 帧间隔时间
local CameraUnit = {}

---获取遮挡相机视线的单位列表
---**适用范围**: 客户端和服务端
---@param castPoints Vector3[] 射线检测目标点列表
---@param ignoreList Unit[] 忽略的单位列表
---@return Unit[] 遮挡视线的单位列表
function CameraUnit:GetPartsObscuringTarget(castPoints, ignoreList) end

---重置相机移动状态
---**适用范围**: 客户端和服务端
function CameraUnit:ResetMovement() end

---天体，可用于太阳/月亮等天空发光体，允许同时存在多个
---**适用范围**: 客户端和服务端
---@class CelestialBody : Unit
---@field AffectedByFog Bool 受雾影响
---@field AngularSize Float 天体在天空中张开的角直径，单位度
---@field Brightness Float 亮度
---@field Color Color 颜色
---@field FollowLightOrientation Bool 跟随光照朝向，开启后天体朝向由 LightingService 的 Orientation 决定，自身 Orientation 不再生效
---@field Orientation Vector3 朝向，FollowLightOrientation 为真时该属性无效
---@field Texture String 贴图
local CelestialBody = {}

---点击检测器是一种可挂载到其他单位上的交互组件，用于检测玩家鼠标左键和右键的点击操作。它支持配置最大激活距离和启用状态，当玩家在有效距离内点击时，会触发对应的事件并传入触发玩家。
---@class ClickDetector : Unit
---@field Enabled Bool 是否启用
---@field MaxActivationDistance Float 最大激活距离
---@field MouseClick Signal<fun(player: Player)> 鼠标左键点击触发。回调参数：player 触发的玩家
---@field RightMouseClick Signal<fun(player: Player)> 鼠标右键点击触发。回调参数：player 触发的玩家
local ClickDetector = {}

---云层
---**适用范围**: 客户端和服务端
---@class Clouds : Unit
---@field AffectedByFog Bool 受雾影响
---@field Color Color 颜色
---@field Coverage Float 覆盖率
---@field Density Float 密度
---@field Speed Float 移动速度
local Clouds = {}

---色彩分级效果
---**适用范围**: 客户端和服务端
---@class ColorGradingEffect : BasePostEffect
---@field Brightness Float 明度
---@field Contrast Float 对比度
---@field Filter Enums.ColorGradingFilter 滤镜
---@field FilterStrength Float 滤镜强度
---@field HighlightsColor Color 高光颜色
---@field HighlightsStrength Float 高光强度
---@field Hue Float 色相
---@field MidtonesColor Color 中间调颜色
---@field MidtonesStrength Float 中间调强度
---@field Saturation Float 饱和度
---@field ShadowsColor Color 阴影颜色
---@field ShadowsStrength Float 阴影强度
---@field Temperature Float 色温
---@field Tint Float 色调
---@field ToningStrength Float 染色总强度
local ColorGradingEffect = {}

---漫画效果
---**适用范围**: 客户端和服务端
---@class ComicEffect : BasePostEffect
---@field ColorLevels Int 色阶层级
---@field HalftoneStrength Float 网点强度
---@field HighlightsColor Color 亮部颜色
---@field OutlineColor Color 描边颜色
---@field OutlineStrength Float 描边强度
---@field OutlineWidth Int 描边宽度
---@field ShadowsColor Color 暗部颜色
---@field SkyColor Color 天空颜色
local ComicEffect = {}

---配置快照（不可变数据视图）。由 ConfigService:GetConfigAsync() 或 GetConfigForPlayerAsync() 创建。
---当后台版本号变化时 Outdated 会被置为 true 并 Fire UpdateAvailable。
---调用 Refresh() 可同步到最新数据。
---@class ConfigSnapshot : Unit
---@field Outdated Bool 当前快照是否已过期
---@field UpdateAvailable Signal<fun()> 后端版本变化时 Fire 一次（通常对应 Outdated 由 false 变 true）
local ConfigSnapshot = {}

---获取一个配置项的值；优先返回试玩覆盖值，否则返回快照锁定的值
---@param key String 配置键名
---@return Any 配置值
function ConfigSnapshot:GetValue(key) end

---获取（或懒创建）某个 key 的变更信号；Refresh 检测到值变化或 SetTestingValue/ClearTestingValue 影响该 key 时 Fire(newValue, oldValue)
---@param key String 配置键名
---@return Signal 变更信号
function ConfigSnapshot:GetValueChangedSignal(key) end

---主动同步到最新已发布配置；完成后 Outdated 复位为 false
function ConfigSnapshot:Refresh() end

---曲线速度运动器
---@class CurveVelMotorUnit : BaseMotorUnit
---@field CurveAccelerationTime Float 加速时长
---@field CurveAngularAcceleration Vector3 角加速度
---@field CurveConstantSpeedTime Float 匀速时长
---@field CurveLinearAcceleration Vector3 直线加速度
---@field CurveVelType Int 运动类型
local CurveVelMotorUnit = {}

---景深效果
---**适用范围**: 客户端和服务端
---@class DepthOfFieldEffect : BasePostEffect
---@field FocusDistance Float 对焦距离
---@field MaxBlurSize Float 最大模糊半径
local DepthOfFieldEffect = {}

---UI按钮节点
---@class EUIButton : EUINodeBase
---@field ButtonDisableColor Color 禁用按钮颜色
---@field ButtonNormalColor Color 常态按钮颜色
---@field ButtonPressColor Color 按下按钮颜色
---@field ButtonText String 按钮文本
---@field ButtonTextColor Color 按钮文本颜色
---@field ButtonTextFont Enums.TextFontType 按钮文本字体
---@field ButtonTextFontSize Int 按钮文本字体大小
---@field DisableImage String 常态图片
---@field Disabled Bool 是否禁用
---@field NormalImage String 常态图片
---@field PressImage String 常态图片
---@field StretchArea Vector4 拉伸区域
---@field StretchAreaPercentEnabled Bool 拉伸区域按百分比计算
local EUIButton = {}

---UI裁切节点
---@class EUIClippingNode : EUINodeBase
---@field AlphaThreshold Float alpha阈值
---@field ClippingEnabled Bool 开启裁切
---@field ClippingImage String 蒙版图片
---@field Inverted Bool 反转裁切
local EUIClippingNode = {}

---UI动效节点
---@class EUIEffect : EUINodeBase
---@field EffectId Int 动效ID
---@field LoopPlay Bool 循环播放
---@field Size Vector2 尺寸
local EUIEffect = {}

function EUIEffect:PlayAnimation() end

function EUIEffect:StopAnimation() end

---UI网格布局容器
---@class EUIGridLayout : EUINodeBase
---@field AutoLayout Bool 自动布局
---@field AutomaticSize Bool 自动扩容
---@field CellPadding Vector2 单元间距(像素)
---@field CellSize Vector2 单元尺寸(像素)
---@field FillDirection Enums.EUIFillDirection 填充方向
---@field FillDirectionMaxCells Int 主轴最大单元数
---@field HorizontalAlignment Enums.EUIHorizontalAlignment 水平对齐
---@field SortOrder Enums.EUISortOrderType 排序依据
---@field StartCorner Enums.EUIGridStartCorner 起始角落
---@field VerticalAlignment Enums.EUIVerticalAlignment 垂直对齐
local EUIGridLayout = {}

function EUIGridLayout:ApplyLayout() end

---UI图片节点
---@class EUIImage : EUINodeBase
---@field Color Color 颜色
---@field Image String 图片
---@field StretchArea Vector4 拉伸区域
---@field StretchAreaPercentEnabled Bool 拉伸区域按百分比计算
local EUIImage = {}

---UI输入框
---@class EUIInputField : EUINodeBase
---@field Font Enums.TextFontType 字体
---@field FontSize Int 字体大小
---@field ItalicEnabled Bool 开启斜体
---@field OutlineColor Color 描边颜色
---@field OutlineEnabled Bool 开启描边
---@field OutlineOpacity Float 描边透明度
---@field OutlineWidth Int 描边宽度
---@field PlaceHolderText String 占位文本
---@field PlaceHolderTextColor Color 占位文本颜色
---@field ShadowColor Color 阴影颜色
---@field ShadowEnabled Bool 开启阴影
---@field ShadowOffset Vector2 阴影偏移
---@field Text String 文本
---@field TextColor Color 文本颜色
---@field TextHorizontalAlignment Enums.EUITextHorizontalAlignment 水平对齐方式
---@field TextVerticalAlignment Enums.EUITextVerticalAlignment 垂直对齐方式
---@field OnDetach Signal<fun()>
local EUIInputField = {}

---UI容器节点
---@class EUILayout : EUINodeBase
---@field ClippingEnabled Bool 开启裁切
local EUILayout = {}

---UI列表布局容器
---@class EUIListLayout : EUINodeBase
---@field AutoLayout Bool 自动布局
---@field AutomaticSize Bool 自动扩容
---@field FillDirection Enums.EUIFillDirection 填充方向
---@field HorizontalAlignment Enums.EUIHorizontalAlignment 水平对齐
---@field Padding Vector2 间距(像素)
---@field SortOrder Enums.EUISortOrderType 排序依据
---@field VerticalAlignment Enums.EUIVerticalAlignment 垂直对齐
---@field Wraps Bool 允许换行
local EUIListLayout = {}

function EUIListLayout:ApplyLayout() end

---UI列表容器
---@class EUIListView : EUINodeBase
---@field BackgroundImage String 背景图片
---@field BackgroundOpacity Float 背景透明度
---@field BounceEnabled Bool 开启反弹
---@field ClippingEnabled Bool 开启裁切
---@field ItemsMargin Int 列表边距
---@field ListviewGravity Enums.EUIListviewGravity 对齐方式
---@field ScrollDirection Enums.EUIScrollDirection 方向
---@field ScrollEnabled Bool 开启滑动
local EUIListView = {}

---@return Float 当前滚动百分比(0~100)
function EUIListView:GetScrollPercent() end

---@param itemIndex Int 子项索引(从0开始)
---@param time Float 滚动时长(秒)
function EUIListView:ScrollToItem(itemIndex, time) end

---@param percent Float 目标百分比(0~100)
---@param time Float 滚动时长(秒)
---@param attenuated Bool 是否衰减
function EUIListView:ScrollToPercent(percent, time, attenuated) end

---UI进度条节点
---@class EUILoadingBar : EUINodeBase
---@field Color Color 颜色
---@field Direction Enums.EUIProgressDirection 方向
---@field Image String 进度图片
---@field Percent Float 进度百分比
local EUILoadingBar = {}

---UI节点
---@class EUINodeBase : Unit
---@field Anchor Vector2 锚点
---@field AnchorXAdaptMode Enums.EUIAnchorAdaptMode 锚点X自适应模式
---@field AnchorXAdaption Float 锚点X自适应
---@field AnchorYAdaptMode Enums.EUIAnchorAdaptMode 锚点Y自适应模式
---@field AnchorYAdaption Float 锚点Y自适应
---@field BottomAdaptMode Enums.EUIAdaptMode 底部自适应模式
---@field BottomAdaption Float 底部自适应
---@field ClickEvent String 点击事件
---@field FlippedX Bool 横向反转
---@field FlippedY Bool 纵向反转
---@field HideEvent String 隐藏事件
---@field LayoutOrder Int 布局序号
---@field LeftAdaptMode Enums.EUIAdaptMode 左边自适应模式
---@field LeftAdaption Float 左边自适应
---@field LocalZOrder Int 层级序号
---@field LongtouchEvent String 长按事件
---@field Opacity Float 透明度
---@field Position Vector2 坐标
---@field RightAdaptMode Enums.EUIAdaptMode 右边自适应模式
---@field RightAdaption Float 右边自适应
---@field Rotation Float 旋转
---@field Scale Vector2 缩放
---@field ShowEvent String 显示事件
---@field Size Vector2 尺寸
---@field SwallowTouchEnabled Bool 是否吞噬触摸
---@field TopAdaptMode Enums.EUIAdaptMode 顶部自适应模式
---@field TopAdaption Float 顶部自适应
---@field TouchBeginAudio String 按下音效
---@field TouchClickAudio String 点击音效
---@field TouchEnabled Bool 是否可触摸
---@field TouchEndAudio String 抬起音效
---@field TouchbeginEvent String 触摸开始事件
---@field TouchendEvent String 触摸结束事件
---@field Visible Bool 是否可见
---@field OnClicked Signal<fun(player: Player)> 回调参数：player 玩家
---@field OnTouchBegan Signal<fun(euiTouchInfo: EUITouchInfo, player: Player)> 回调参数：euiTouchInfo 交互参数, player 玩家
---@field OnTouchEnded Signal<fun(euiTouchInfo: EUITouchInfo, player: Player)> 回调参数：euiTouchInfo 交互参数, player 玩家
---@field OnTouchMoved Signal<fun(euiTouchInfo: EUITouchInfo, player: Player)> 回调参数：euiTouchInfo 交互参数, player 玩家
local EUINodeBase = {}

---把 UI 世界坐标转换为相对本节点的局部坐标。仅客户端可调用，服务端调用会报错
---@param worldPos Vector2 世界坐标
---@return Vector2 局部坐标
function EUINodeBase:ConvertToLocalPosition(worldPos) end

---把相对本节点的局部坐标转换为 UI 世界坐标。仅客户端可调用，服务端调用会报错
---@param localPos Vector2 局部坐标
---@return Vector2 世界坐标
function EUINodeBase:ConvertToWorldPosition(localPos) end

---返回当前 UI 节点从 UI 根节点到自身（不含 UI 根节点）的 '.' 分隔路径字符串。例：节点层级 root.A.B 中，B:GetFullPath() 返回 'A.B'
---@return String UI 路径字符串（'.' 分隔）
function EUINodeBase:GetFullPath() end

---返回本节点在 UI 世界坐标系下的位置。仅客户端可调用，服务端调用会报错。无父节点时返回 (0, 0)
---@return Vector2 世界坐标
function EUINodeBase:GetWorldPosition() end

---判断给定的 UI 世界坐标是否落在本节点范围内。仅客户端可调用，服务端调用会报错
---@param pos Vector2 世界坐标
---@return Bool 是否命中
function EUINodeBase:HitTest(pos) end

function EUINodeBase:Release() end

function EUINodeBase:RemoveFromParent() end

function EUINodeBase:Retain() end

---@param endOpacity Float 目标透明度(0~1)
---@param easingDirection Enums.EasingDirection 缓动方向(默认 Out)
---@param easingStyle Enums.EasingStyle 缓动样式(默认 Quad)
---@param time Float 时长(秒,默认 1)
---@param override Bool 是否抢占 Opacity 通道旧 Tween(默认 false)
---@param callback function 完成或被抢占时触发的回调(status:TweenStatus)
---@return Bool 是否成功启动新 Tween
function EUINodeBase:TweenOpacity(endOpacity, easingDirection, easingStyle, time, override, callback) end

---@param endPosition Vector2 目标位置(绝对像素)
---@param easingDirection Enums.EasingDirection 缓动方向(默认 Out)
---@param easingStyle Enums.EasingStyle 缓动样式(默认 Quad)
---@param time Float 时长(秒,默认 1)
---@param override Bool 是否抢占同通道旧 Tween(默认 false)
---@param callback function 完成或被抢占时触发的回调(status:TweenStatus)
---@return Bool 是否成功启动新 Tween
function EUINodeBase:TweenPosition(endPosition, easingDirection, easingStyle, time, override, callback) end

---@param endSize Vector2 目标尺寸(绝对像素)
---@param easingDirection Enums.EasingDirection 缓动方向(默认 Out)
---@param easingStyle Enums.EasingStyle 缓动样式(默认 Quad)
---@param time Float 时长(秒,默认 1)
---@param override Bool 是否抢占同通道旧 Tween(默认 false)
---@param callback function 完成或被抢占时触发的回调(status:TweenStatus)
---@return Bool 是否成功启动新 Tween
function EUINodeBase:TweenSize(endSize, easingDirection, easingStyle, time, override, callback) end

---@param endSize Vector2 目标尺寸(绝对像素)
---@param endPosition Vector2 目标位置(绝对像素)
---@param easingDirection Enums.EasingDirection 缓动方向(默认 Out)
---@param easingStyle Enums.EasingStyle 缓动样式(默认 Quad)
---@param time Float 时长(秒,默认 1)
---@param override Bool 是否抢占 Pos/Size 两通道旧 Tween(默认 false)
---@param callback function 完成或被抢占时触发的回调(status:TweenStatus)
---@return Bool 是否成功启动新 Tween
function EUINodeBase:TweenSizeAndPosition(endSize, endPosition, easingDirection, easingStyle, time, override, callback) end

---UI环形进度条节点
---@class EUIProgressTimer : EUINodeBase
---@field Color Color 颜色
---@field Direction Enums.EUIProgressDirection 方向
---@field Image String 进度图片
---@field Percent Float 进度百分比
local EUIProgressTimer = {}

---UI富文本
---@class EUIRichTextLabel : EUINodeBase
---@field ArrangeMode Enums.EUIArrangeMode 排列模式
---@field AutoScrollProgress Float 自动滚动循环间距
---@field AutoScrollSpeed Float 自动滚动速度
---@field AutoSizeEnabled Bool 是否自动缩小字号
---@field EnableMaxHeight Bool 启用最大高度限制
---@field EnableMaxWidth Bool 启用最大宽度限制
---@field Font Enums.TextFontType 字体
---@field FontSize Int 字体大小
---@field ItalicEnabled Bool 开启斜体
---@field LineSpacing Int 行间距
---@field MinFontSize Int 最小字号
---@field OutlineColor Color 描边颜色
---@field OutlineEnabled Bool 开启描边
---@field OutlineOpacity Float 描边透明度
---@field OutlineWidth Int 描边宽度
---@field OverflowPolicy Enums.EUIOverflowPolicy 溢出策略
---@field ShadowColor Color 阴影颜色
---@field ShadowEnabled Bool 开启阴影
---@field ShadowOffset Vector2 阴影偏移
---@field ShrinkFontSizeStep Float 字体缩小步长
---@field SingleLineMaxWidth Int 单行最大宽度
---@field SingleLineMinWidth Int 单行最小宽度
---@field Text String 文本
---@field TextColor Color 文本颜色
---@field TextHorizontalAlignment Enums.EUITextHorizontalAlignment 水平对齐方式
---@field TextSpacing Int 字间距
---@field TextVerticalAlignment Enums.EUITextVerticalAlignment 垂直对齐方式
---@field WrapMaxHeight Int 换行最大高度
---@field WrapMinHeight Int 换行最小高度
---@field WrapWidth Int 换行宽度
local EUIRichTextLabel = {}

---UI根节点
---@class EUIRootNode : EUINodeBase
local EUIRootNode = {}

---UI场景界面节点
---@class EUISceneNode : EUINodeBase
---@field AutoScaleEnabled Bool 开启自动缩放(近大远小)
---@field BindSocket String 绑定位置（socket）
---@field InheritVisible Bool 跟随Unit显隐
---@field MaxVisibleDistance Float 最大可见距离(距摄像机, 负数则永远可见)
---@field Position Vector3 位置
local EUISceneNode = {}

---@param unit Unit 位置
---@param socket String 位置
function EUISceneNode:AttachUnit(unit, socket) end

---UI简易富文本
---@class EUISimpleRichTextLabel : EUINodeBase
---@field AutoSizeEnabled Bool 是否自动缩小字号
---@field Font Enums.TextFontType 字体
---@field FontSize Int 字体大小
---@field ItalicEnabled Bool 开启斜体
---@field LineSpacing Int 行间距
---@field MinFontSize Int 最小字号
---@field OutlineColor Color 描边颜色
---@field OutlineEnabled Bool 开启描边
---@field OutlineOpacity Float 描边透明度
---@field OutlineWidth Int 描边宽度
---@field OverflowStrategy Enums.EUIOverflowStrategy 超框策略
---@field ResetSizePolicy Enums.EUIResetSizePolicy 爆框策略
---@field ShadowColor Color 阴影颜色
---@field ShadowEnabled Bool 开启阴影
---@field ShadowOffset Vector2 阴影偏移
---@field Text String 文本
---@field TextColor Color 文本颜色
---@field TextHorizontalAlignment Enums.EUITextHorizontalAlignment 水平对齐方式
---@field TextSpacing Int 字间距
---@field TextVerticalAlignment Enums.EUITextVerticalAlignment 垂直对齐方式
local EUISimpleRichTextLabel = {}

---UI表格布局容器
---@class EUITableLayout : EUINodeBase
---@field AutoLayout Bool 自动布局
---@field AutomaticSize Bool 自动扩容
---@field FillEmptySpaceColumns Bool 列均分空间
---@field FillEmptySpaceRows Bool 行均分空间
---@field MajorAxis Enums.EUITableMajorAxis 主轴模式
---@field Padding Vector2 间距(像素)
local EUITableLayout = {}

function EUITableLayout:ApplyLayout() end

---UI文本
---@class EUITextLabel : EUINodeBase
---@field Font Enums.TextFontType 字体
---@field FontSize Int 字体大小
---@field ItalicEnabled Bool 开启斜体
---@field OutlineColor Color 描边颜色
---@field OutlineEnabled Bool 开启描边
---@field OutlineOpacity Float 描边透明度
---@field OutlineWidth Int 描边宽度
---@field ShadowColor Color 阴影颜色
---@field ShadowEnabled Bool 开启阴影
---@field ShadowOffset Vector2 阴影偏移
---@field Text String 文本
---@field TextColor Color 文本颜色
---@field TextHorizontalAlignment Enums.EUITextHorizontalAlignment 水平对齐方式
---@field TextVerticalAlignment Enums.EUITextVerticalAlignment 垂直对齐方式
local EUITextLabel = {}

---特效
---@class EffectUnit : Unit
---@field AsyncLoad Bool 异步加载
---@field BlendFactor Float 融合系数
---@field ColorStrength Int 颜色强度
---@field DiffuseColor Color 基础颜色
---@field Duration Float 持续时间
---@field EffectBindData EffectBindData EffectUnit有2中bind模式, 1、有合法的parent，就跟随parent（basepart，attachemnt）,2、设置EffectBindData绑定信息,主动设置EffectBindData视为第一优先级，如果想恢复跟随Parent，EffectBindData 需要赋空实现
---@field EffectEndBindData EffectBindData 终点绑定数据（socket）
---@field EffectId String 特效资源
---@field EnableColor Bool 启用自定义颜色
---@field EnemyEffectEnable Bool 启动敌我特效区分
---@field EnemyEffectId String 敌方显示特效
---@field ForceLoop Bool 开启后强制特效循环播放；关闭时按特效资源自带的播放方式执行（资源本身是循环的仍会循环）。对 efx 与 sfx 特效均生效。
---@field IsMute Bool 是否静音
---@field PlayRate Float 播放速率
---@field Position Vector3 位置
---@field Rotation Quaternion 旋转
---@field Scale Vector3 缩放
---@field Visible Bool 可见性
---@field Volume Float 音量
local EffectUnit = {}

---设置连线特效终点
---@param otherUnit SpaceUnit 单位预制
---@param socket String 挂点
---@param offset Vector3 位置偏移
function EffectUnit:EndposAttach(otherUnit, socket, offset) end

---设置特效位移
---@param targetPos Vector3 目标位置
---@param speed Float 线速度(米/秒)
---@param callBack function 结束回调
function EffectUnit:MoveTo(targetPos, speed, callBack) end

---移除特效的声音
function EffectUnit:RemoveSound() end

---重播特效
function EffectUnit:Restart() end

---绑定特效
---@param otherUnit SpaceUnit 单位预制
---@param socket String 挂点
---@param offset Vector3 位置偏移
---@param bindType Enums.EffectBindType 绑定类型
function EffectUnit:SetBindData(otherUnit, socket, offset, bindType) end

---设置特效的颜色、强度和混合比列
---@param color Color 颜色
---@param strength Int 强度
---@param blendFactor Float 混合比例
function EffectUnit:SetColor(color, strength, blendFactor) end

---设置特效时长
---@param duration Float 时长
function EffectUnit:SetDuration(duration) end

---设置特效静音
function EffectUnit:SetMute() end

---设置特效的坐标
---@param position Vector3 位置
function EffectUnit:SetPosition(position) end

---设置特效的播放速率
---@param rate Float 速率
function EffectUnit:SetRate(rate) end

---设置特效的旋转
---@param rotate Quaternion 旋转
function EffectUnit:SetRotation(rotate) end

---设置特效的缩放
---@param scale Vector3 缩放
function EffectUnit:SetScale(scale) end

---设置特效的可见性
---@param visible Bool 可见性
function EffectUnit:SetVisible(visible) end

---设置连线特效起点
---@param otherUnit SpaceUnit 单位预制
---@param socket String 挂点
---@param offset Vector3 位置偏移
---@param bindType Enums.EffectBindType 绑定类型
function EffectUnit:StartposAttach(otherUnit, socket, offset, bindType) end

---蛋形生物控制器，通过EggyUnit.Controller获取使用，在通用生物控制器的基础上扩展蛋仔特有的玩法表现，包括抓举、前扑、翻滚以及质量条等独特能力。
---@class EggyController : BaseController
---@field ClimbEnabled Bool 开启攀爬
---@field ClimbSpeed Float 攀爬速度
---@field LiftedEnabled Bool 能否被抓举
---@field RollCDTime Float 滚动CD时间
---@field RollChargeTime Float 滚动充能时长
---@field RollSpeed Float 滚动速度
---@field RollTime Float 滚动持续时长
---@field OnLiftBegin Signal<fun(liftedUnit: SpaceUnit)> 开始抓举其他单位时触发。回调参数：liftedUnit 举起的单位
---@field OnLiftEnd Signal<fun()> 结束抓举（扔出/打断）时触发
---@field OnLiftedBegin Signal<fun(liftunit: EggyUnit)> 被其他生物抓举起时触发。回调参数：liftunit 举起当前对象的生物
---@field OnLiftedEnd Signal<fun()> 结束被抓举状态时触发
local EggyController = {}

---执行一次翻滚
function EggyController:Fling() end

---尝试抓举身前的目标，可指定强制抓举对象
---@param force_lift_unit? EggyUnit 强制抓举目标
function EggyController:Lift(force_lift_unit) end

---执行一次前扑
function EggyController:Rush() end

---扔出当前抓举的对象
function EggyController:Throw() end

---蛋形生物，玩家在游戏中操控的蛋仔角色，也可作为怪物/NPC等存在。具备空间位置、姿态、外观等生命体属性。EggyUnit.Controller获取控制器实现移动、跳跃等行为状态，EggyUnit.Animator获取动画组件，EggyUnit.EggyAppearance获取外观组件进行使用
---@class EggyUnit : SpaceUnit
---@field Animator Animator 关联的动画控制器组件引用，运行时自动从子节点中查找
---@field Controller EggyController 蛋形生物控制器
---@field CustomAppearanceId String 自定义外观ID
---@field EggyAppearance EggyAppearance 蛋形生物外观
---@field EnableAppearance Bool 使用蛋形外观
---@field EnableController Bool 是否创建Controller
---@field Position Vector3 位置
---@field RenderMeshId String 模型资源ID
---@field Rotation Quaternion 旋转
---@field Scale Vector3 缩放
---@field UseCustomAppearance Bool 使用自定义外观
---@field Visible Bool 可见性
local EggyUnit = {}

---获取{#0}的网络拥有者
---@return Player 网络拥有者
function EggyUnit:GetNetworkOwner() end

---获取位置
---@return Vector3 位置
function EggyUnit:GetPosition() end

---获取旋转
---@return Quaternion 旋转
function EggyUnit:GetRotation() end

---获取缩放
---@return Vector3 缩放
function EggyUnit:GetScale() end

---获取Yaw朝向
---@return Float Yaw朝向
function EggyUnit:GetYaw() end

---设置{#0}的网络拥有者
---@param player Player 玩家
function EggyUnit:SetNetworkOwner(player) end

---设置位置
---@param pos Vector3 坐标
function EggyUnit:SetPosition(pos) end

---设置旋转
---@param rotation Quaternion 旋转
function EggyUnit:SetRotation(rotation) end

---设置缩放
---@param scale Vector3 缩放
function EggyUnit:SetScale(scale) end

---文件网格
---@class FileMesh : Unit
---@field MeshId String 网格资产ID
---@field Offset Vector3 偏移
---@field Scale Vector3 缩放
---@field TextureId String 纹理资产ID
---@field VertexColor Color 顶点颜色
local FileMesh = {}

---寻路路径
---@class FindingPathUnit : SpaceUnit
---@field Name String 名称
local FindingPathUnit = {}

---添加路点
---@param position Vector3 路点世界位置
---@return Attachment? 新创建的路点 Attachment，失败返回 nil
function FindingPathUnit:AddPoint(position) end

---获取路点数量
---@return Int 路点数量
function FindingPathUnit:GetPointCount() end

---获取路点坐标列表
---@return Table[] 每个元素为 { Position = Vector3 } 结构的 table。
function FindingPathUnit:GetWaypoints() end

---移除路点
---@param index Int 路点索引
function FindingPathUnit:RemovePoint(index) end

---雾效
---**适用范围**: 客户端和服务端
---@class Fog : Unit
---@field AtmosphericBrightness Float 大气雾亮度
---@field AtmosphericColor Color 大气雾颜色
---@field AtmosphericDensity Float 大气雾浓度
---@field AtmosphericEndDistance Float 大气雾结束距离
---@field AtmosphericStartDistance Float 大气雾起始距离
---@field Enabled Bool 启用
---@field HeightFogBeginHeight Float 高度雾起始高度
---@field HeightFogColor Color 高度雾颜色
---@field HeightFogDensity Float 高度雾浓度
---@field HeightFogEndHeight Float 高度雾结束高度
---@field SunInscatterAtmosphericBlend Float 散射受大气雾影响程度
---@field SunInscatterBrightness Float 散射亮度
---@field SunInscatterColor Color 散射颜色
---@field SunInscatterExponent Float 散射收束度
---@field SunInscatterStartDistance Float 散射起始距离
local Fog = {}

---通用容器单位，自身不携带任何属性和渲染表现，仅用于在场景层级树中组织和分组子 Unit 实例，便于逻辑归类和批量管理。
---@class Folder : Unit
local Folder = {}

---渐变天空
---**适用范围**: 客户端和服务端
---@class GradientSky : BaseSky
---@field Center Float 过渡位置
---@field Direction Enums.GradientSkyDirection 渐变方向
---@field EndColor Color 结束颜色
---@field Softness Float 过渡柔度
---@field StartColor Color 起始颜色
local GradientSky = {}

---铰链约束用于在两个物理部件之间创建单轴旋转连接，类似门铰链或膝关节。支持 Motor（恒速旋转）和 Servo（目标角度）两种驱动模式，并可设置角度限制。使用时需设置 Attachment0 和 Attachment1 指向两个已存在的 Attachment。物理约束建议在服务端创建。
---@class HingeConstraint : Unit
---@field ActuatorType Int 驱动类型
---@field AngularResponsiveness Float Servo响应灵敏度(当前仅存储)
---@field AngularSpeed Float Servo角速度(rad/s, 当前仅存储)
---@field AngularVelocity Float 目标角速度(Motor模式, rad/s)
---@field Attachment0 Attachment Attachment0
---@field Attachment1 Attachment Attachment1
---@field Enabled Bool 启用约束
---@field LimitsEnabled Bool 启用角度限制
---@field LowerAngle Float 最小角度(度)
---@field MotorMaxAcceleration Float Motor最大角加速度(rad/s², 当前仅存储)
---@field MotorMaxTorque Float Motor最大扭矩
---@field Radius Float 可视化半径
---@field Restitution Float 弹性(0-1)
---@field ServoMaxTorque Float Servo最大扭矩
---@field TargetAngle Float 目标角度(Servo模式, 度)
---@field UpperAngle Float 最大角度(度)
local HingeConstraint = {}

---人形生物控制器，通过HumanUnit.Controller获取使用，在通用生物控制器的基础上扩展人形特有的能力。
---@class HumanController : BaseController
---@field ClimbEnabled Bool 是否启用攀爬能力，开启后单位可在符合条件的墙体上攀爬
---@field ClimbMoveDirection Vector3 攀爬方向（x=左右, z=上下）
---@field EvaluateStateMachine Bool 是否启用内置状态机评估（移动、跳跃、下落等）。关闭后状态机副作用暂停，但脚本驱动 ChangeState 仍可用
---@field InertiaEnabled Bool 是否启用引擎层惯性位移。设为 false 时，人物在 Move / MoveTo 停止后立即静止，不再因惯性继续向前滑动；恢复为 true 时还原原有反向加速度
---@field NameBarOffset Float 名称标签在头顶上方的垂直偏移高度（m）
---@field SeatPart Unit 当前正在乘坐的座椅 Unit 引用，未坐下时为 nil
---@field Sit Bool 运行时只读标记，表示单位当前是否处于坐下状态
---@field TargetPoint Vector3 AI 寻路或玩家点击移动的目标世界坐标
---@field Climbing Signal<fun(speed: Float)> 单位处于攀爬状态时每帧触发，携带当前攀爬速度。回调参数：speed 当前攀爬速度
---@field FallingDown Signal<fun(active: Bool)> 单位进入或离开绊倒状态时触发。回调参数：active true=进入绊倒，false=离开绊倒
---@field FreeFalling Signal<fun(active: Bool)> 单位开始自由下落或落地时触发。回调参数：active true=开始下落，false=落地
---@field GettingUp Signal<fun(active: Bool)> 单位开始或完成起身动作时触发。回调参数：active true=开始起身，false=起身完成
---@field OnClimbEnd Signal<fun()> 攀爬结束时触发
---@field OnClimbStart Signal<fun()> 攀爬开始时触发，空中/跳跃上墙不发此事件
---@field Running Signal<fun(speed: Float)> 单位处于奔跑状态时每帧触发，携带当前水平移动速度。回调参数：speed 当前水平移动速度
---@field Seated Signal<fun(active: Bool, seat: Unit)> 单位坐下或起身时触发，携带当前座位 Unit 引用。回调参数：active true=坐下，false=起身, seat 座位 Unit
local HumanController = {}

---获取单位当前的移动速度向量（含水平和垂直分量）
---@return Vector3 当前移动速度向量
function HumanController:GetMoveVelocity() end

---获取单位相对于站立表面的速度向量，用于检测滑步等状态
---@return Vector3 相对于站立表面的速度向量（世界空间方向）
function HumanController:GetRelativeVelocityAtFloor() end

---人形生物
---@class HumanUnit : SpaceUnit
---@field AngularVelocity Vector3 当前角速度（弧度/秒），运行时只读，反映单位绕各轴的旋转速率
---@field Animator Animator 关联的动画控制器组件引用，运行时自动从子节点中查找
---@field BodyType Int 刚体类型：Static(静态，不受力)、Kinematic(运动学，仅脚本控制移动)、Dynamic(动态，受物理模拟)
---@field CanCollide Bool 是否启用碰撞检测，关闭后该单位将穿过其他物理对象
---@field CenterOfMass Vector3 相对于模型原点的质心偏移，影响旋转和受力行为
---@field CollisionGroup String 单位所属的碰撞预设组名称，决定默认的碰撞过滤规则
---@field Controller HumanController 人形生物控制器
---@field CustomAppearanceId String 自定义外观ID
---@field EnableAnimScript Bool 单位创建时是否自动挂载动画蓝图脚本
---@field EnableAnimator Bool 单位创建时是否自动挂载Animator
---@field EnableController Bool 是否创建Controller
---@field GravityEnabled Bool 是否受全局重力影响，关闭后单位将漂浮
---@field HumanSkinColor Vector4 肤色 HSL 调整 4 元组，x=色相偏移(默认0，范围-1~1)，y=饱和度(默认1，范围0~2)，z=亮度(默认1，范围0~2)，w=换色强度(默认1，范围0~1)；相对贴图基准色计算，默认 (0,1,1,1) 表示不染色
---@field IndividualGravityValue Vector3 自定义重力加速度向量
---@field LinearVelocity Vector3 当前线速度（m/s），运行时只读，反映单位在世界空间中的移动速度
---@field Mass Float 单位质量，影响碰撞反馈和受力效果，仅 Dynamic 类型有效
---@field Massless Bool 是否将质量视为零，启用后碰撞不会产生反作用力
---@field PhysicsActive Bool 是否启用物理模拟，关闭后单位不受重力、碰撞等物理影响
---@field Position Vector3 单位在世界空间中的位置坐标
---@field RenderMeshId String 单位使用的骨骼网格资源路径，支持 official:// 协议引用官方资源
---@field Rotation Quaternion 单位在世界空间中的旋转，以四元数表示
---@field RotationLocked Bool 是否锁定旋转自由度，启用后物理模拟不会改变单位朝向
---@field Scale Vector3 单位在三个轴向上的缩放倍数，默认 (1,1,1) 表示原始尺寸
---@field UseCustomAppearance Bool 使用自定义外观
---@field UseIndividualGravity Bool 是否覆盖全局重力，启用后将使用 IndividualGravityValue 指定的重力方向与大小
---@field Visible Bool 控制单位模型是否在场景中渲染显示
---@field OnCollisionEnter Signal<fun(otherUnit: Unit)> 当本单位与其他 Unit 开始碰撞时触发。回调参数：otherUnit 碰撞到的单位
---@field OnCollisionExit Signal<fun(otherUnit: Unit)> 当本单位与其他 Unit 结束碰撞时触发。回调参数：otherUnit 结束碰撞的单位
local HumanUnit = {}

---动态添加与该碰撞组的碰撞关系，使本单位与指定碰撞组内的对象产生碰撞
---@param groupName String 碰撞组名
function HumanUnit:AddCollisionWithGroup(groupName) end

---通过资源ID动态添加蒙皮，叠加在单位基础模型上（仅自定义模型生效）
---@param assetId String 蒙皮资源路径
function HumanUnit:AddMeshByAssetId(assetId) end

---动态禁用与指定单位之间的碰撞检测，双方将互相穿过
---@param targetUnit SpaceUnit 目标单位
function HumanUnit:AddNoCollisionPairWithUnit(targetUnit) end

---在单位局部空间中的指定位置施加力，会产生扭矩效果
---@param force Vector3 施加的力
---@param localPosition Vector3 局部空间坐标系下的力量的施加点
function HumanUnit:ApplyForceAtLocalPosition(force, localPosition) end

---在世界空间中的指定位置施加力，力作用点偏离质心时会产生扭矩
---@param force Vector3 施加的力
---@param worldPosition Vector3 世界空间坐标系下的力量的施加点
function HumanUnit:ApplyForceAtWorldPosition(force, worldPosition) end

---在世界空间中向单位质心施加一个力向量，不产生扭矩
---@param force Vector3 施加的力
function HumanUnit:ApplyForceToCenterOfMass(force) end

---获取当前单位动态添加的所有碰撞组名称列表
---@return String[]
function HumanUnit:GetCollisionWithGroups() end

---获取当前拥有该单位网络所有权的玩家
---@return Player 网络拥有者
function HumanUnit:GetNetworkOwner() end

---获取当前单位禁用了碰撞检测的所有单位列表
---@return SpaceUnit[]
function HumanUnit:GetNoCollisionPairUnitList() end

---获取单位物理位置的世界坐标
---@return Vector3 位置
function HumanUnit:GetPosition() end

---获取单位渲染模型的位置（可能与物理位置存在插值偏差）
---@return Vector3 显示位置
function HumanUnit:GetRenderPosition() end

---获取单位渲染模型的旋转（可能与物理旋转存在插值偏差）
---@return Quaternion 显示旋转
function HumanUnit:GetRenderRotation() end

---获取单位物理旋转的四元数表示
---@return Quaternion 旋转
function HumanUnit:GetRotation() end

---获取单位当前的缩放比例
---@return Vector3 缩放
function HumanUnit:GetScale() end

---获取单位绕世界 Y 轴的水平旋转角度（弧度）
---@return Float Yaw朝向
function HumanUnit:GetYaw() end

---一次性恢复与所有单位的碰撞检测，清空不碰撞列表
function HumanUnit:RemoveAllNoCollisionPairWithUnit() end

---动态移除与该碰撞组的碰撞关系，使本单位不再与指定碰撞组内的对象碰撞
---@param groupName String 碰撞组名
function HumanUnit:RemoveCollisionWithGroup(groupName) end

---通过资源ID移除已添加的蒙皮，同时清理对应的蒙皮染色数据（仅自定义模型生效）
---@param assetId String 要移除的蒙皮资源路径
function HumanUnit:RemoveMeshByAssetId(assetId) end

---恢复与指定单位之间的碰撞检测
---@param targetUnit SpaceUnit 目标单位
function HumanUnit:RemoveNoCollisionPairWithUnit(targetUnit) end

---为人形指定蒙皮的染色区域设置颜色，需先通过AddMeshByAssetId添加该蒙皮
---@param assetId String 蒙皮网格资源路径，需与AddMeshByAssetId传入的一致
---@param colorKey Enums.HumanMeshColor 要设置的染色区域类型
---@param color Color 要设置的目标颜色
---@param materialIndex Int 目标材质索引
function HumanUnit:SetMeshColor(assetId, colorKey, color, materialIndex) end

---为人形指定蒙皮的材质索引设置贴图，需先通过AddMeshByAssetId添加该蒙皮
---@param meshAssetId String 蒙皮网格资源路径，需与AddMeshByAssetId传入的一致
---@param textureAssetId String 要应用的贴图资源路径
---@param materialIndex Int 目标材质索引
function HumanUnit:SetMeshTexture(meshAssetId, textureAssetId, materialIndex) end

---为单位指定染色区域设置颜色（仅自定义模型生效）
---@param colorKey Enums.HumanMeshColor 要设置的染色区域类型
---@param color Color 要设置的目标颜色
---@param materialIndex Int 目标材质索引
function HumanUnit:SetModelColor(colorKey, color, materialIndex) end

---为人形自定义模型指定材质索引替换贴图资源（仅自定义模型生效）
---@param assetId String 贴图资源路径
---@param materialIndex Int 目标材质索引
function HumanUnit:SetModelTexture(assetId, materialIndex) end

---将该单位的网络所有权转移给指定玩家，拥有者负责物理模拟和状态同步
---@param player Player 玩家
function HumanUnit:SetNetworkOwner(player) end

---设置单位物理位置的世界坐标，会触发碰撞检测和受力计算
---@param pos Vector3 坐标
function HumanUnit:SetPosition(pos) end

---设置单位物理旋转的四元数
---@param rotation Quaternion 旋转
function HumanUnit:SetRotation(rotation) end

---设置单位的缩放比例，影响模型大小和碰撞体积
---@param scale Vector3 缩放
function HumanUnit:SetScale(scale) end

---水墨效果
---**适用范围**: 客户端和服务端
---@class InkWashEffect : BasePostEffect
---@field DesaturationStrength Float 去色强度
---@field InkDensity Float 水墨浓度
---@field OutlineStrength Float 描边强度
---@field OutlineWidth Float 描边宽度
---@field PaperColor Color 纸张颜色
local InkWashEffect = {}

---镜头雨水效果
---**适用范围**: 客户端和服务端
---@class LensRainEffect : BasePostEffect
---@field CenterClearRadius Float 中心清晰区半径
---@field DropletDensity Float 雨点密度
---@field DropletRotationRandomness Float 雨点旋转随机度
---@field DropletSpeed Float 雨点速度
---@field DropletStrength Float 雨点强度
---@field StreakDensity Float 雨痕密度
---@field StreakSpeed Float 雨痕滑落速度
---@field StreakStrength Float 雨痕强度
local LensRainEffect = {}

---直线运动器
---@class LinearMotorUnit : BaseMotorUnit
---@field LinearVelocity Vector3 线速度
---@field MotorType Int 运动器类型
local LinearMotorUnit = {}

---连线特效
---@class LinkEffectUnit : EffectUnit
---@field EndBindUnit Unit 终点绑定单位
---@field EndPosition Vector3 终点坐标
---@field UseEndBindUnit Bool 终点绑定单位
local LinkEffectUnit = {}

---本地脚本，仅在本地客户端生效
---@class LocalScript : BaseScript
local LocalScript = {}

---ModelUnit是一个用于容纳子对象的容器单位，继承自SpaceUnit。常用于将多个子对象组合为一个整体进行移动和管理。
---@class ModelUnit : SpaceUnit
---@field Position Vector3 容器在世界空间中的位置坐标，该属性为语法糖，实际使用PivotTo
---@field PrimaryPart SpaceUnit 模型的核心部件，作为模型整体移动和物理模拟的参考基准。设置后，模型的枢轴（Pivot）将跟随该部件。未设置时，模型枢轴由 WorldPivot 决定。未设置 PrimaryPart 时，在首次设置 WorldPivot 之前，模型枢轴默认为 (0,0,0)，PivotTo 将以该默认值计算位移。建议在使用 PivotTo 前先主动设置 WorldPivot 或 PrimaryPart。
---@field Rotation Quaternion 容器在世界空间中的旋转，以四元数表示，该属性为语法糖，实际使用PivotTo
---@field WorldPivot CFrame 模型在世界空间中的枢轴位置。仅用于更新 ModelUnit 自身的枢轴，不会移动子对象。当未设置 PrimaryPart 时，PivotTo、MoveTo 等轴心操作以该值为参考基准计算位移增量。设置 PrimaryPart 后，该属性被忽略，模型枢轴改为跟随 PrimaryPart。新创建模型的枢轴在首次设置 WorldPivot 之前默认位于原点 (0,0,0)。设置方式：通过 unit.WorldPivot = cf 赋值，或在 world:CreateUnit("ModelUnit", { WorldPivot = cf }) 参数中指定。
local ModelUnit = {}

---将模型整体移动到世界空间中的指定位置
---@param position Vector3 世界空间中的目标坐标
function ModelUnit:MoveTo(position) end

---模块脚本，可被其他脚本代码require
---@class ModuleScript : BaseScript
local ModuleScript = {}

---Path 对象用于保存一次寻路计算结果。建议复用同一个 Path 对象多次调用 ComputeAsync 获取新路径；不再使用时必须显式调用 Destroy() 释放。ComputeAsync 当前是同步执行接口，不会挂起协程；未来实现可能调整为协程接口，请不要依赖其始终同步返回。
---**适用范围**: 客户端和服务端
---@class Path : Unit
---@field Status Enums.PathStatus 路径计算状态。初始值为 NoPath；ComputeAsync 成功后变为 Success，失败或无可达路径时为 NoPath。
---@field Blocked Signal<fun(segmentIndex: Int)> 路径线段被动态 NavMesh 重烘焙结果判定为阻断时触发；PathfindingService.HasDynamicNavMesh 为 false 时，不会因运行时障碍、Link 或 Modifier 变化自动触发。回调参数：segmentIndex 被阻断的线段索引，1-based。
---@field Unblocked Signal<fun(segmentIndex: Int)> 路径线段被动态 NavMesh 重烘焙结果判定为恢复通行时触发；PathfindingService.HasDynamicNavMesh 为 false 时，不会因运行时障碍、Link 或 Modifier 变化自动触发。回调参数：segmentIndex 恢复通行的线段索引，1-based。
local Path = {}

---根据起点和终点计算路径并更新 Status 与路点列表。当前实现为同步执行，不是协程；未来可能变为协程接口。
---**适用范围**: 客户端和服务端
---@param start Vector3 寻路起点的世界坐标。
---@param dest Vector3 寻路终点的世界坐标。
function Path:ComputeAsync(start, dest) end

---获取导航区域标签当前对应的寻路代价。
---**适用范围**: 客户端和服务端
---@param area_index String 导航区域或 Link/Modifier 的 Label。
---@return Float 区域寻路代价值。
function Path:GetAreaCost(area_index) end

---获取最近一次成功计算出的路径路点列表。Status 不是 Success 时返回空列表；返回的是列表副本，修改该列表不会影响 Path 内部保存的路点。
---**适用范围**: 客户端和服务端
---@return PathWaypoint[] PathWaypoint 数组副本。
function Path:GetWaypoints() end

---在导航网格上从起点到终点执行射线检测。
---**适用范围**: 客户端和服务端
---@param startPosition Vector3 射线起点的世界坐标。
---@param endPosition Vector3 射线终点的世界坐标。
---@return PathHitInfo 导航网格射线检测结果对象。
function Path:Raycast(startPosition, endPosition) end

---在导航网格上查找距离源坐标最近的可行走位置。
---**适用范围**: 客户端和服务端
---@param sourcePosition Vector3 采样查询的世界坐标。
---@param maxDistance Float 从源坐标开始搜索的最大半径。
---@param areaMask Int 用于限制可采样区域的掩码。此参数暂未使用
---@return Vector3 最近的导航网格坐标；采样失败时返回 nil。
function Path:SamplePosition(sourcePosition, maxDistance, areaMask) end

---设置导航区域标签对应的寻路代价，会影响后续 ComputeAsync 的路径选择。
---**适用范围**: 客户端和服务端
---@param area_index String 导航区域或 Link/Modifier 的 Label。
---@param cost Float 该区域的寻路代价值。
function Path:SetAreaCost(area_index, cost) end

---PathfindingLink 用于在两个 Attachment 之间建立导航网格外连接。编辑器预摆并已参与烘焙的链接不受动态 NavMesh 开关影响；仅运行时创建、销毁或修改 Attachment、IsBidirectional、Label 时，需要 PathfindingService.HasDynamicNavMesh 为 true 才会触发 tile 重烘焙并动态加入、移除或更新导航网格。
---**适用范围**: 客户端和服务端
---@class PathfindingLink : Unit
---@field Attachment0 Attachment 运行时虚拟属性。getter 会根据 AttachmentID0 返回对应 Attachment；setter 可直接赋值 Attachment 单位并自动写入 AttachmentID0。推荐运行时代码使用该属性，而不是直接设置 AttachmentID0。
---@field Attachment1 Attachment 运行时虚拟属性。getter 会根据 AttachmentID1 返回对应 Attachment；setter 可直接赋值 Attachment 单位并自动写入 AttachmentID1。推荐运行时代码使用该属性，而不是直接设置 AttachmentID1。
---@field AttachmentID0 Int 起始 Attachment 的 UnitId。运行时创建 PathfindingLink 时推荐使用 Attachment0 属性直接赋值 Attachment 单位，不推荐手动初始化该 ID 字段；直接设置 ID 虽然也可生效，但可读性和类型安全较差。动态 NavMesh 开启时修改会触发相关 tile 重烘焙；未开启时不会更新导航网格。
---@field AttachmentID1 Int 终点 Attachment 的 UnitId。运行时创建 PathfindingLink 时推荐使用 Attachment1 属性直接赋值 Attachment 单位，不推荐手动初始化该 ID 字段；直接设置 ID 虽然也可生效，但可读性和类型安全较差。动态 NavMesh 开启时修改会触发相关 tile 重烘焙；未开启时不会更新导航网格。
---@field IsBidirectional Bool 控制该链接是否允许双向通行。动态 NavMesh 开启时修改会触发链接所在 tile 重烘焙；未开启时不会更新导航网格。
---@field Label String 链接对应的导航区域标签，可配合 CreatePath 的 Costs 或 Path:SetAreaCost 设置区域代价。动态 NavMesh 开启时修改会触发链接所在 tile 重烘焙；未开启时不会更新导航网格。
local PathfindingLink = {}

---PathfindingModifier 用于标记 Parent 物理体在导航网格中的区域、穿越性和烘焙策略。编辑器预摆并已参与烘焙的修饰器不受动态 NavMesh 开关影响；仅运行时创建、销毁、修改 Parent 或修改 Label、PassThrough、BakeMode 时，需要 PathfindingService.HasDynamicNavMesh 为 true 才会触发 tile 重烘焙并动态影响导航网格。
---**适用范围**: 客户端和服务端
---@class PathfindingModifier : Unit
---@field BakeMode Enums.BakeMode 决定 Parent 物理体如何参与运行时导航网格重烘焙。动态 NavMesh 开启时修改会触发 Parent 覆盖 tile 重烘焙；未开启时运行时修改不会更新导航网格。
---@field Label String 动态 NavMesh 开启时，用于标记 Parent 物理体烘焙出的导航区域；可配合 CreatePath 的 Costs 或 Path:SetAreaCost 设置代价。未开启时运行时修改不会更新导航网格。
---@field PassThrough Bool 控制 Parent 物理体对应的导航区域是否可穿越。动态 NavMesh 开启时修改会触发 Parent 覆盖 tile 重烘焙；未开启时运行时修改不会更新导航网格。
local PathfindingModifier = {}

---摆锤运动器
---@class PendulumMotorUnit : BaseMotorUnit
---@field AngularVelocity Vector3 角速度
local PendulumMotorUnit = {}

---纯物理组件
---@class PhysicsUnit : BasePart
---@field AngularDamping Float 角速度的阻尼系数，值越大旋转减速越快，仅对动态(Dynamic)物体生效
---@field AngularVelocity Vector3 物体的初始角速度，仅对动态(Dynamic)物体生效
---@field BodyType Int 物体的物理运动类型：静态(Static)不可修改，运动学(Kinematic)仅通过脚本逻辑驱动，动态(Dynamic)参与完整物理模拟
---@field CanCollide Bool 是否参与物理碰撞，关闭后物体将穿透其他物体
---@field CanQuery Bool 是否参与空间射线检测（Raycast、Spherecast 等），关闭后射线将穿透此物体
---@field CanTouch Bool 其他物体碰到此物体时，是否触发此物体的碰撞事件
---@field CanTrigger Bool 此物体碰到其他物体时，是否触发对方的碰撞事件
---@field CenterOfMass Vector3 物体在局部空间中的质心偏移位置
---@field Climbable Bool 玩家角色是否可以攀爬此物体，仅对静态(Static)物体生效
---@field CollisionGroup String 物体所属的碰撞组名称，用于按碰撞组规则过滤碰撞关系
---@field CustomPhysicalProperties PhysicalProperties 自定义物理材质参数（摩擦力、弹性、密度等），为空时使用默认值
---@field GravityEnabled Bool 是否受重力影响，仅对动态(Dynamic)物体生效
---@field IndividualGravityValue Vector3 自定义重力的方向和大小，默认为 (0, -9.8, 0)
---@field LinearDamping Float 线速度的阻尼系数，值越大减速越快，仅对动态(Dynamic)物体生效
---@field LinearVelocity Vector3 物体的初始线速度，仅对动态(Dynamic)物体生效
---@field Mass Float 物体的质量，仅对动态(Dynamic)物体生效
---@field Massless Bool 启用后此物体的质量不计入父级装配体的总质量
---@field ModelBindParent Bool 启用后，当父节点为 WorldUnit、RenderUnit、TriggerUnit、PhysicsUnit 等支持父子带动的场景单位时，当前单位将整体跟随父节点运动，保持与父节点的相对位置和旋转。运行时可通过脚本设置 .ModelBindParent = true/false 动态切换该行为。
---@field PhysicsActive Bool 是否启用物理模拟，关闭后物体不参与碰撞和物理计算
---@field PhysicsMeshId String 物理资源ID
---@field UseIndividualGravity Bool 启用后使用自定义的重力方向和大小替代全局重力
---@field OnCollisionEnter Signal<fun(otherUnit: Unit)> 当其他物体开始与此物体发生碰撞时触发。回调参数：otherUnit 与之发生碰撞的另一个物体
---@field OnCollisionExit Signal<fun(otherUnit: Unit)> 当其他物体与此物体结束碰撞时触发。回调参数：otherUnit 结束碰撞的另一个物体
---@field OnLocalCollisionEnter Signal<fun(info: CollisionCallbackInfo)> 当其他物体开始与此物体发生碰撞时在本地触发，回调参数为 CollisionCallbackInfo。回调参数：info 碰撞回调信息
---@field OnLocalCollisionExit Signal<fun(info: CollisionCallbackInfo)> 当其他物体与此物体结束碰撞时在本地触发；若碰撞对方在结束碰撞前被销毁，也会补发该事件。回调参数为 CollisionCallbackInfo。回调参数：info 碰撞回调信息
local PhysicsUnit = {}

---将物体添加到指定碰撞组，使其遵循该组的碰撞规则
---@param groupName String 要加入的碰撞组名称
function PhysicsUnit:AddCollisionWithGroup(groupName) end

---与指定单位建立互不碰撞关系
---@param targetUnit SpaceUnit 要互不碰撞的目标单位
function PhysicsUnit:AddNoCollisionPairWithUnit(targetUnit) end

---在局部空间的指定位置施加一个持续的力
---@param force Vector3 世界空间中的力向量
---@param localPosition Vector3 物体局部空间中的施力点坐标
function PhysicsUnit:ApplyForceAtLocalPosition(force, localPosition) end

---在世界空间的指定位置施加一个持续的力
---@param force Vector3 世界空间中的力向量
---@param worldPosition Vector3 世界空间中的施力点坐标
function PhysicsUnit:ApplyForceAtWorldPosition(force, worldPosition) end

---在质心位置施加一个持续的力
---@param force Vector3 世界空间中的力向量
function PhysicsUnit:ApplyForceToCenterOfMass(force) end

---在质心位置施加一个瞬时冲量
---@param impulse Vector3 冲量向量，方向和大小决定瞬时速度变化
function PhysicsUnit:ApplyImpulse(impulse) end

---在局部空间的指定位置施加一个瞬时冲量
---@param impulse Vector3 冲量向量
---@param localPosition Vector3 物体局部空间中的冲量施加点坐标
function PhysicsUnit:ApplyImpulseAtLocalPosition(impulse, localPosition) end

---在世界空间的指定位置施加一个瞬时冲量
---@param impulse Vector3 冲量向量
---@param worldPosition Vector3 世界空间中的冲量施加点坐标
function PhysicsUnit:ApplyImpulseAtWorldPosition(impulse, worldPosition) end

---对物体施加一个持续的力矩（旋转力）
---@param torque Vector3 各轴方向的力矩大小
function PhysicsUnit:ApplyTorque(torque) end

---获取物体当前所属的所有碰撞组名称
---@return String[]
function PhysicsUnit:GetCollisionWithGroups() end

---获取当前与此物体互不碰撞的所有单位列表
---@return SpaceUnit[]
function PhysicsUnit:GetNoCollisionPairUnitList() end

---获取物体在指定世界坐标位置处的线速度
---@param position Vector3 要查询速度的世界空间坐标点
---@return Vector3
function PhysicsUnit:GetVelocityAtPosition(position) end

---清除所有互不碰撞关系，恢复与所有物体的碰撞
function PhysicsUnit:RemoveAllNoCollisionPairWithUnit() end

---将物体从指定碰撞组中移除
---@param groupName String 要移除的碰撞组名称
function PhysicsUnit:RemoveCollisionWithGroup(groupName) end

---取消与指定单位的互不碰撞关系
---@param targetUnit SpaceUnit 要恢复碰撞的目标单位
function PhysicsUnit:RemoveNoCollisionPairWithUnit(targetUnit) end

---像素化效果
---**适用范围**: 客户端和服务端
---@class PixelateEffect : BasePostEffect
---@field PixelCount Float 像素块数量
local PixelateEffect = {}

---玩家对象，代表当前局内的一名玩家，具有唯一标识，通过player.Character可以获取和切换玩家对应的操控单位如EggyUnit。客户端通过 Players.LocalPlayer 获取本地玩家对象，服务端可通过 Players:GetPlayerByUserId(userId) 获取指定玩家对象。玩家对象包含玩家的基本信息属性、玩家角色相关事件以及与玩家交互的函数接口，也是 RemoteEvent 网络消息通信的唯一标识
---**适用范围**: 客户端和服务端
---@class Player : Unit
---@field Camp Camp 阵营
---@field Character EggyUnit 玩家控制的单位
---@field PlayerGui PlayerGui 玩家的 PlayerGui 对象
---@field UserId String 玩家唯一标识
---@field AuthorSubscribeChanged Signal<fun(oldValue: Int, newValue: Int)> 当玩家对当前地图作者的订阅状态变更时触发。回调参数：oldValue 变更前状态（0=未订阅，1=已订阅）, newValue 变更后状态（0=未订阅，1=已订阅）
---@field CharacterAdded Signal<fun(character: EggyUnit)> 当玩家角色创建时触发。回调参数：character 玩家角色
---@field CharacterRemoving Signal<fun(character: EggyUnit)> 当玩家角色销毁时触发。回调参数：character 玩家角色
---@field Chatted Signal<fun(message: String, channelName: String)> 当玩家发送聊天消息时触发。回调参数：message 聊天文本内容, channelName 所在频道名
---@field Idled Signal<fun(afkTime: Float)> 当玩家无输入操作超过 2 分钟后触发，后续定期触发。回调参数：afkTime 玩家无输入操作的时间（秒）
---@field InFanClubChanged Signal<fun(oldValue: Int, newValue: Int)> 当玩家粉丝团加入状态变更时触发。回调参数：oldValue 变更前状态（0=未加入，1=已加入）, newValue 变更后状态（0=未加入，1=已加入）
---@field LoseClient Signal<fun()> 当玩家客户端掉线/失联时触发
---@field MapFavoriteChanged Signal<fun(oldValue: Int, newValue: Int)> 当玩家对当前地图的收藏状态变更时触发。回调参数：oldValue 变更前状态（0=未收藏，1=已收藏）, newValue 变更后状态（0=未收藏，1=已收藏）
---@field MapLikeChanged Signal<fun(oldValue: Int, newValue: Int)> 当玩家对当前地图的点赞状态变更时触发。回调参数：oldValue 变更前状态（0=未点赞，1=已点赞）, newValue 变更后状态（0=未点赞，1=已点赞）
---@field OnRelay Signal<fun()> 当玩家顶号登录客户端就绪后触发
---@field OnTeleport Signal<fun(teleportState: Enums.TeleportState, mapId: String, spawnName: String)> 当玩家传送状态变化时触发。回调参数：teleportState 传送状态, mapId 目标地图编号, spawnName 出生点名称
local Player = {}

---请求添加好友
---**适用范围**: 客户端和服务端
---@param userId String 玩家编号
function Player:AddFriendWith(userId) end

---获取玩家触发的自定义事件信号
---**适用范围**: 客户端和服务端
---@param eventName String 自定义事件名
---@return Signal 自定义事件信号
function Player:GetCustomEventSignal(eventName) end

---获取玩家加入游戏时携带的数据
---**适用范围**: 客户端和服务端
---@return JoinData 玩家加入数据字典
function Player:GetJoinData() end

---获取玩家名称
---**适用范围**: 客户端和服务端
---@return String 玩家名称
function Player:GetName() end

---获取玩家网络延迟（秒）
---**适用范围**: 客户端和服务端
---@return Float 玩家网络延迟
function Player:GetNetworkPing() end

---获取蛋仔岛上的组队标识
---**适用范围**: 客户端和服务端
---@return String 组队标识
function Player:GetPartyId() end

---检查指定玩家是否为我的好友
---**适用范围**: 客户端和服务端
---@param userId String 玩家编号
---@param checkCallback function 检查结果回调
function Player:IsFriendsWithAsync(userId, checkCallback) end

---是否加入了粉丝团
---**适用范围**: 客户端和服务端
---@return Bool 是否加入了粉丝团
function Player:IsInFanClub() end

---是否收藏本地图
---**适用范围**: 客户端和服务端
---@return Bool 是否收藏本地图
function Player:IsMapFavorited() end

---是否点赞本地图
---**适用范围**: 客户端和服务端
---@return Bool 是否点赞本地图
function Player:IsMapLiked() end

---是否是乐园会员
---**适用范围**: 客户端和服务端
---@return Bool 是否是乐园会员
function Player:IsVip() end

---将玩家踢出游戏
---**适用范围**: 客户端和服务端
---@param reason? String 踢出原因提示，踢出前向该玩家展示 tips
function Player:Kick(reason) end

---异步加载玩家角色
---**适用范围**: 客户端和服务端
function Player:LoadCharacterAsync() end

---将角色复位到出生点
---**适用范围**: 客户端和服务端
---@param resetCamera Bool 是否重置相机
function Player:ResetCharacterToSpawnLocation(resetCamera) end

---预设链接
---@class PresetLink : Unit
---@field Icon String 单位图标资源路径，仅编辑时使用，运行时不参与同步
local PresetLink = {}

---预置天空模板，内置多套精选固定材质的天空球方案。即选即用，无需调参，专注呈现纯粹的场景背景氛围。
---**适用范围**: 客户端和服务端
---@class PresetSky : BaseSky
---@field SkyboxTexture String 天空球背景贴图
---@field Template Enums.PresetSkyTemplate 模板
local PresetSky = {}

---滑轨约束用于在两个物理部件之间创建单轴滑动连接，限制其中一个部件只能沿固定轴相对另一个部件平移。支持 Motor（恒速滑动）和 Servo（目标位置）两种驱动模式，并可设置线性位置限制。使用时需设置 Attachment0 和 Attachment1 指向两个已存在的 Attachment。物理约束建议在服务端创建。
---@class PrismaticConstraint : Unit
---@field Active Bool 当前是否激活
---@field ActuatorType Int 驱动类型
---@field Attachment0 Attachment Attachment0
---@field Attachment1 Attachment Attachment1
---@field CurrentPosition Float 当前滑动位置(空间单位)
---@field Enabled Bool 启用约束
---@field LimitsEnabled Bool 启用线性限制
---@field LinearResponsiveness Float Servo线性响应
---@field LowerLimit Float 最小位置(空间单位)
---@field MotorMaxAcceleration Float Motor最大加速度(当前仅存储)
---@field MotorMaxForce Float Motor最大力
---@field Restitution Float 弹性(0-1)
---@field ServoMaxForce Float Servo最大力
---@field Speed Float Servo速度(空间单位/秒)
---@field TargetPosition Float Servo目标位置(空间单位)
---@field UpperLimit Float 最大位置(空间单位)
---@field Velocity Float Motor目标速度(空间单位/秒)
local PrismaticConstraint = {}

---四色渐变天空
---**适用范围**: 客户端和服务端
---@class QuadGradientSky : BaseSky
---@field LowerColor Color 偏下颜色
---@field LowerHeight Float 偏下高度
---@field LowerToUpperSoftness Float 偏下至偏上柔度
---@field NadirColor Color 天底颜色
---@field NadirHeight Float 天底高度
---@field NadirToLowerSoftness Float 天底至偏下柔度
---@field Orientation Vector3 旋转
---@field UpperColor Color 偏上颜色
---@field UpperHeight Float 偏上高度
---@field UpperToZenithSoftness Float 偏上至天顶柔度
---@field ZenithColor Color 天顶颜色
---@field ZenithHeight Float 天顶高度
local QuadGradientSky = {}

---触发区域
---@class RenderTriggerUnit : TriggerUnit
---@field CastShadow Bool 控制模型是否向场景投射阴影；启用自定义外观后该属性不生效
---@field CustomAppearanceId String 自定义外观ID
---@field DisplayModelId String 预览模型
---@field LocalTransparencyModifier Float 本地客户端的透明度乘数，用于第一人称遮挡等本地渲染效果，不同步到其他客户端
---@field ModelAlpha Float 控制模型的整体透明度，0 为完全透明，1 为完全不透明
---@field ModelBindParent Bool 启用后，当父节点为 WorldUnit、RenderUnit、TriggerUnit、PhysicsUnit 等支持父子带动的场景单位时，当前模型渲染表现将跟随父节点的变换自动同步。运行时可通过脚本设置 .ModelBindParent = true/false 动态切换该行为。
---@field ModelColor1 Color 模型染色区域1的颜色；启用自定义外观后该属性不生效
---@field ModelColor2 Color 模型染色区域2的颜色；启用自定义外观后该属性不生效
---@field ModelColor3 Color 模型染色区域3的颜色；启用自定义外观后该属性不生效
---@field ModelColor4 Color 模型染色区域4的颜色；启用自定义外观后该属性不生效
---@field ModelVisible Bool 控制模型是否可见，隐藏后仍参与物理碰撞
---@field OcclusionType Int 遮挡玩家时的规则
---@field PhysicsMeshId String 物理网格资源ID。缺省时，若初始创建时传入了 RenderMeshId，则默认使用该 RenderMeshId 作为物理资源；后续修改 .RenderMeshId 不会影响 PhysicsMeshId
---@field RenderMeshId String 模型的资源路径，用于指定渲染使用的网格资源；启用自定义外观后该属性不生效
---@field SkinId String 模型使用的皮肤资源ID，用于切换模型外观；启用自定义外观后该属性不生效
---@field UseCustomAppearance Bool 使用自定义外观
local RenderTriggerUnit = {}

---切换 RenderMeshId 并自动应用新模型的默认皮肤：默认皮肤 >1 个时进入多槽位模式（逐 Submesh 一个默认皮并回填默认染色），单个/无默认皮肤时回到单皮肤模式并写入默认 SkinId（含默认染色回填）。双端可调用，服务端权威（客户端仅本机生效）；自定义外观开启期间不可用
---@param renderMeshId String 模型资源ID
function RenderTriggerUnit:SetRenderMeshWithDefaultSkin(renderMeshId) end

---设置单位的自定义贴图，整模型生效，传空字符串恢复默认贴图；双端可调用（服务端广播全端，客户端仅本机生效）；自定义外观期间不可用；换模型/换皮肤/开启自定义外观时自动清除
---@param textureAssetId String 贴图资源ID
function RenderTriggerUnit:SetTexture(textureAssetId) end

---RenderUnit是一种可创建的3D空间组件，具备渲染表现能力。常用于场景中需要模型展示的装饰物件。
---@class RenderUnit : BasePart
---@field CastShadow Bool 控制模型是否向场景投射阴影；启用自定义外观后该属性不生效
---@field CustomAppearanceId String 自定义外观的资源ID，启用自定义外观后生效
---@field LocalTransparencyModifier Float 本地客户端的透明度乘数，用于第一人称遮挡等本地渲染效果，不同步到其他客户端
---@field ModelAlpha Float 控制模型的整体透明度，0 为完全透明，1 为完全不透明
---@field ModelBindParent Bool 启用后，当父节点为 WorldUnit、RenderUnit、TriggerUnit、PhysicsUnit 等支持父子带动的场景单位时，当前模型渲染表现将跟随父节点的变换自动同步。运行时可通过脚本设置 .ModelBindParent = true/false 动态切换该行为。
---@field ModelColor1 Color 模型染色区域1的颜色；启用自定义外观后该属性不生效
---@field ModelColor2 Color 模型染色区域2的颜色；启用自定义外观后该属性不生效
---@field ModelColor3 Color 模型染色区域3的颜色；启用自定义外观后该属性不生效
---@field ModelColor4 Color 模型染色区域4的颜色；启用自定义外观后该属性不生效
---@field ModelVisible Bool 控制模型是否可见，隐藏后仍参与物理碰撞
---@field OcclusionType Int 当模型遮挡住摄像机与玩家之间的视线时的处理策略
---@field RenderMeshId String 模型的资源路径，用于指定渲染使用的网格资源；启用自定义外观后该属性不生效
---@field SkinId String 模型使用的皮肤资源ID，用于切换模型外观；启用自定义外观后该属性不生效
---@field TransparentRenderBias Int 控制半透明物体的渲染层级偏置，值越小越先渲染。仅影响半透明物体，不透明物体不受此偏置影响。取值范围 [-15, 16]，超出会被截断到边界。注意：仅当遮挡规则(OcclusionType)为 组件半透明/镜头前推/玩家虚影 时生效；为 不处理 时本偏置不生效
---@field UseCustomAppearance Bool 启用后使用自定义外观替代默认模型渲染
local RenderUnit = {}

---切换 RenderMeshId 并自动应用新模型的默认皮肤：默认皮肤 >1 个时进入多槽位模式（逐 Submesh 一个默认皮并回填默认染色），单个/无默认皮肤时回到单皮肤模式并写入默认 SkinId（含默认染色回填）。双端可调用，服务端权威（客户端仅本机生效）；自定义外观开启期间不可用
---@param renderMeshId String 模型资源ID
function RenderUnit:SetRenderMeshWithDefaultSkin(renderMeshId) end

---刚性约束用于将两个物理部件完全固定在一起，使其之间不能有任何相对运动（位置和旋转均锁定）。使用时需设置 Attachment0 和 Attachment1 指向两个已存在的 Attachment。物理约束建议在服务端创建。
---@class RigidConstraint : Unit
---@field Active Bool 当前是否激活
---@field Attachment0 Attachment Attachment0
---@field Attachment1 Attachment Attachment1
---@field Enabled Bool 启用约束
local RigidConstraint = {}

---杆约束用于在两个物理部件之间保持固定的距离，类似刚性连杆。与刚性约束不同，杆约束允许两部件在保持距离的前提下自由旋转。使用时需设置 Attachment0 和 Attachment1 指向两个已存在的 Attachment，并通过 Length 属性指定杆长。物理约束建议在服务端创建。
---@class RodConstraint : Unit
---@field Active Bool 当前是否激活
---@field Attachment0 Attachment Attachment0
---@field Attachment1 Attachment Attachment1
---@field CurrentDistance Float 当前距离(空间单位)
---@field Enabled Bool 启用约束
---@field Length Float 杆长(空间单位)
---@field LimitAngle0 Float Attachment0端角度限制(度, 当前仅存储)
---@field LimitAngle1 Float Attachment1端角度限制(度, 当前仅存储)
---@field LimitsEnabled Bool 启用端部角度限制(当前仅存储)
---@field Thickness Float 可视化粗细(当前仅存储)
local RodConstraint = {}

---服务器脚本，仅在服务器侧生效
---@class Script : BaseScript
local Script = {}

---座椅
---@class SeatUnit : BasePart
---@field Disabled Bool 是否禁用
---@field Occupant Unit 当前乘客
---@field RenderMeshId String 模型资源ID
---@field OnOccupantChanged Signal<fun(occupant: Unit)> 回调参数：occupant 当前乘客
local SeatUnit = {}

---从一个矩形平面发光，像一个发光的面板。适合做电视屏幕、LED广告牌、窗户透光等。
---**适用范围**: 客户端和服务端
---@class SimpleAreaLight : SimpleLight
---@field Brightness Float 亮度
---@field Color Color 颜色
---@field LightPattern String 切换面光源的照射图案
---@field Size Vector2 尺寸
local SimpleAreaLight = {}

---面状自发光体的暗调版本，颜色更深、氛围更沉。
---**适用范围**: 客户端和服务端
---@class SimpleAreaShadowLight : SimpleLight
---@field Color Color 颜色
---@field Size Vector2 尺寸
---@field Transparency Float 控制光源模型的透明度，值越小越透明（越暗）
local SimpleAreaShadowLight = {}

---这是一类装饰性的发光物体——它们自身会亮、会发光，但不会照亮周围的其他物体。适合做路灯、霓虹灯、灯具造型等装饰用途。
---**适用范围**: 客户端和服务端
---@class SimpleLight : Unit
---@field CloseEvent String 关灯事件
---@field Enabled Bool 启用
---@field OpenEvent String 开灯事件
---@field Position Vector3 位置
---@field Rotation Quaternion 旋转
---@field Scale Vector3 缩放
local SimpleLight = {}

---沿一条线段发光，两端可设置不同颜色形成渐变。适合做霓虹灯管、光剑、灯带等。
---**适用范围**: 客户端和服务端
---@class SimpleLineLight : SimpleLight
---@field Brightness Float 亮度
---@field Color Color 颜色
---@field Color2 Color 颜色2
---@field Pivot Float 中间点
---@field Radius Float 半径
local SimpleLineLight = {}

---线状自发光体的暗调版本，颜色更深、氛围更沉。同样支持双色渐变。
---**适用范围**: 客户端和服务端
---@class SimpleLineShadowLight : SimpleLight
---@field Color Color 颜色
---@field Color2 Color 颜色2
---@field Pivot Float 中间点
---@field Transparency Float 控制光源模型的透明度，值越小越透明（越暗）
local SimpleLineShadowLight = {}

---从一个点向四周发光，看起来像一个发光的球。适合做灯泡、火把、魔法球等。
---**适用范围**: 客户端和服务端
---@class SimplePointLight : SimpleLight
---@field AttenuationEnable Bool 启用衰减
---@field Brightness Float 亮度
---@field Color Color 颜色
---@field Radius Float 半径
local SimplePointLight = {}

---点状自发光体的暗调版本，颜色更深、氛围更沉。适合做低亮度氛围灯、暗调装饰灯。
---**适用范围**: 客户端和服务端
---@class SimplePointShadowLight : SimpleLight
---@field AttenuationEnable Bool 启用衰减
---@field Color Color 颜色
---@field Transparency Float 控制光源模型的透明度，值越小越透明（越暗）
local SimplePointShadowLight = {}

---从一个点向特定方向锥形发光。可以显示光束特效。适合做手电筒、舞台追光、车灯等。
---**适用范围**: 客户端和服务端
---@class SimpleSpotLight : SimpleLight
---@field Brightness Float 亮度
---@field Color Color 颜色
---@field InnerAngleFactor Float 内角因子
---@field Radius Float 半径
---@field ShowSfx Bool 显示光束特效
local SimpleSpotLight = {}

---锥状自发光体的暗调版本，颜色更深、氛围更沉。
---**适用范围**: 客户端和服务端
---@class SimpleSpotShadowLight : SimpleLight
---@field Color Color 颜色
---@field InnerAngleFactor Float 内角因子
---@field Transparency Float 控制光源模型的透明度，值越小越透明（越暗）
local SimpleSpotShadowLight = {}

---骨骼挂点
---@class SkeletalSocketMount : Unit
---@field SocketName String 挂点名称
---@field SocketOffset Vector3 挂点位移
---@field SocketRotation Quaternion 挂点旋转
local SkeletalSocketMount = {}

---素描效果
---**适用范围**: 客户端和服务端
---@class SketchEffect : BasePostEffect
---@field DenseStrokeStrength Float 密集笔触强度
---@field DenseThreshold Float 密集线条阈值
---@field DesaturationStrength Float 去色强度
---@field MediumStrokeStrength Float 中度笔触强度
---@field MediumThreshold Float 中度线条阈值
---@field OutlineStrength Float 描边强度
---@field OutlineWidth Int 描边宽度
---@field PaperColor Color 纸张颜色
---@field PaperLightness Float 纸张亮度
---@field SceneOpacity Float 画面不透明度
---@field SparseStrokeStrength Float 稀疏笔触强度
---@field SparseThreshold Float 稀疏线条阈值
---@field StrokeColor Color 笔触颜色
---@field StrokeDensity Float 笔触密度
---@field VignetteZoom Float 暗角缩放
local SketchEffect = {}

---皮肤组件，作为数据覆盖层挂载在父单位下，用于覆盖父单位的皮肤渲染表现。通过SkinId指定皮肤资源，并支持通过ModelColor1-4自定义各染色区域颜色、通过MaterialParam覆盖材质参数。当SkinId生效时，父单位会使用SkinUnit携带的皮肤数据替代自身默认外观；属性变更或父子关系变化时会自动通知父单位刷新渲染。
---@class SkinUnit : Unit
---@field MaterialParam MaterialParam 皮肤的材质参数覆盖，用于修改模型的材质渲染属性（如金属度、粗糙度、自发光等）。设置后会覆盖父单位的默认材质表现。
---@field MaterialParamList MaterialParam[] 材质参数列表
---@field ModelColor1 Color 模型第1染色区域的颜色覆盖值。仅当皮肤模型的color_mask包含第1位（值为1）时生效，用于自定义该区域的渲染颜色。
---@field ModelColor2 Color 模型第2染色区域的颜色覆盖值。仅当皮肤模型的color_mask包含第2位（值为2）时生效，用于自定义该区域的渲染颜色。
---@field ModelColor3 Color 模型第3染色区域的颜色覆盖值。仅当皮肤模型的color_mask包含第3位（值为4）时生效，用于自定义该区域的渲染颜色。
---@field ModelColor4 Color 模型第4染色区域的颜色覆盖值。仅当皮肤模型的color_mask包含第4位（值为8）时生效，用于自定义该区域的渲染颜色。
---@field SkinId String 皮肤资源标识符，用于指定当前SkinUnit引用的皮肤资源。设置后会通过AssetService加载对应的皮肤数据（染色、材质等），并覆盖父单位的默认渲染外观。
local SkinUnit = {}

---普通天空
---**适用范围**: 客户端和服务端
---@class Sky : BaseSky
---@field DistortionEnabled Bool 启用扰动
---@field DistortionFrequency Float 扰动频率
---@field DistortionStrength Float 扰动强度
---@field Orientation Vector3 旋转
---@field SkyboxTexture String 天空球背景贴图
---@field Template Enums.SkyTemplate 模板
---@field YOffset Float 垂直偏移
local Sky = {}

---音组
---@class SoundGroup : Unit
---@field Volume Float 音量
local SoundGroup = {}

---3D 空间音效
---@class SoundUnit : Unit
---@field CampRoleId Int 所属阵营
---@field Duration Float 设置音效强制播放窗口，时长后到期即销毁（非音频本身时长，无论是否在播）
---@field FadeDistance Float 衰减距离
---@field Looped Bool 循环播放
---@field Playing Bool 自动播放
---@field SoundId String 音效资源
---@field SoundType String 音效类型
---@field Speed Float 播放速率
---@field Volume Float 音量
---@field Played Signal<fun()> 播放开始时触发
---@field Stopped Signal<fun()> 播放停止时触发
local SoundUnit = {}

---播放音效{#0}
function SoundUnit:Play() end

---设置音效{#0}播放时长{#1}(设置时长后到期即销毁（无论是否在播）)
---@param duration Float 时长
function SoundUnit:SetDuration(duration) end

---设置音效（3D）{#0}衰减距离{#1}
---@param FadeDistance Float 速率
function SoundUnit:SetFadeDistance(FadeDistance) end

---设置音效（3D）{#0}位置{#1}
---@param position Vector3 位置
function SoundUnit:SetPosition(position) end

---设置音效{#0}的播放速率{#1}
---@param Speed Float 速率
function SoundUnit:SetSpeed(Speed) end

---设置音效{#0}的播放音量为{#1}
---@param Volume Int 音量
function SoundUnit:SetVolume(Volume) end

---设置音效{#0}的播放音量为{#1}，速率{#2}
---@param Volume Int 音量
---@param Speed Float 速率
function SoundUnit:SetVolumeSpeed(Volume, Speed) end

---停止音效
function SoundUnit:Stop() end

---SpaceUnit是具有空间变换（位置、旋转、缩放）的单位基类，所有存在于3D世界中的对象（如WorldUnit、ModelUnit）均继承自此类。提供轴心点（Pivot）操作、标签管理和空间层级查询等核心能力。
---@class SpaceUnit : Unit
---@field EcaPath String ECA 触发器资源路径，用于关联可视化触发器逻辑
---@field Tags String[] 组件拥有的标签集合，用于 CollectionService 分类检索
local SpaceUnit = {}

---为单位添加一个标签，标签可用于 CollectionService 的分类检索
---@param tag String 要添加的标签名称
function SpaceUnit:AddTag(tag) end

---对轴心点施加增量 CFrame 变换，相对于当前姿态进行偏移
---@param delta CFrame 要施加的增量 CFrame 变换
function SpaceUnit:ApplyPivotDelta(delta) end

---沿父节点链向上查找，返回层级树中最顶层的 SpaceUnit 对象
---@return SpaceUnit 层级树中最顶层的 SpaceUnit，若自身已是顶层则返回自身
function SpaceUnit:FindTopLevel() end

---获取单位的轴心点 CFrame，由世界变换和局部偏移综合计算得出
---@return CFrame 轴心点的坐标变换矩阵
function SpaceUnit:GetPivot() end

---检查单位是否拥有指定标签
---@param tag String 要检查的标签名称
---@return Bool 是否拥有指定标签
function SpaceUnit:HasTag(tag) end

---判断当前单位是否为层级树中的顶层 SpaceUnit（即没有 SpaceUnit 类型的父节点）
---@return Bool 是否为顶层对象
function SpaceUnit:IsTopLevel() end

---将单位移动到指定的 CFrame 位置，会同步更新所有子对象使其保持相对偏移不变
---@param cframe CFrame 目标轴心点的坐标变换矩阵
function SpaceUnit:PivotTo(cframe) end

---移除单位上的指定标签
---@param tag String 要移除的标签名称
function SpaceUnit:RemoveTag(tag) end

---将单位沿指定方向平移，偏移量在对象自身坐标系下计算
---@param delta Vector3 在对象自身坐标系下的平移向量
function SpaceUnit:TranslateBy(delta) end

---出生点
---@class SpawnLocationUnit : WorldUnit
---@field CampId Int 阵营id
---@field Capacity Int 容纳上限
---@field EggyPrefabId String 预设蛋仔
---@field InheritPrefabAppearance Bool 是否继承预设外观
---@field Owner Int 所属玩家
---@field RangeBirth Bool 是否在范围内出生
---@field RenderMeshId String 模型的资源路径，用于指定渲染使用的网格资源；启用自定义外观后该属性不生效
---@field SkinId String 皮肤ID
local SpawnLocationUnit = {}

---星星
---**适用范围**: 客户端和服务端
---@class Stars : Unit
---@field AffectedByFog Bool 受雾影响
---@field Brightness Float 亮度
---@field Color Color 颜色
---@field Coverage Float 覆盖率
---@field Density Float 密度
---@field TwinkleSpeed Float 闪烁速度
local Stars = {}

---贴面UI容器
---@class SurfaceGui : BasePart
---@field Brightness Float 亮度，0.0~10.0，默认 1.0
---@field CanvasSize Vector2 画布逻辑尺寸（像素），需非零。仅 FixedSize 模式驱动布局
---@field Enabled Bool 总渲染开关。关闭后画布不渲染，子节点与内部结构不受影响
---@field LightInfluence Float 受场景光照影响程度，0.0~1.0，默认 1.0
---@field MaxDistance Float 世界单位，超出该距离则剔除不渲染；0 表示不限制
---@field PixelsPerWorldUnit Vector2 每轴像素密度，分量需 > 0。仅 PixelsPerWorldUnit 模式生效
---@field WorldScale Vector3 画布在世界中的尺寸（各轴缩放）
local SurfaceGui = {}

---3D文字组件
---@class TextUnit : Unit
---@field BindSocket String 绑定挂点
---@field Content String 文字内容
---@field FontName Enums.TextFontType 字体名称
---@field FontSize Int 字体大小
---@field GradientAngle Float 文本颜色渐变角度
---@field GradientColorEnable Bool 是否开启渐变色
---@field GradientColors Color[] 文本颜色渐变列表
---@field Height Float 文字框高度
---@field HoriAlign Enums.HorizontalAlignmentType 水平对齐方式
---@field LineSpacing Float 行间距
---@field LineWrap Bool 是否自动换行
---@field OutlineColor Color 描边颜色
---@field OutlineWidth Float 描边宽度
---@field OverflowScrollSpacing Float 跑马滚动间距
---@field OverflowScrollSpeed Float 跑马滚动速度
---@field OverflowStrategy Enums.TextOverflowStrategy 文本超框策略
---@field Position Vector3 位置
---@field ReverseDirection Bool 纵向时从右到左显示
---@field Rotation Quaternion 旋转
---@field Scale Vector3 缩放
---@field TextColor Color 文本颜色
---@field TextSkew Float 文本倾斜角度
---@field VertAlign Enums.VerticalAlignmentType 垂直对齐方式
---@field VerticalDirection Bool 是否纵向显示
---@field Visible Bool 是否可见
---@field Width Float 文字框宽度
local TextUnit = {}

---工具单位，支持装备(Equipped)/卸下(Unequipped)/激活(Activated)/停用(Deactivated)等操作的工具类型。
---@class Tool : BackpackItem
---@field CanBeDropped Bool 可丢弃
---@field Enabled Bool 可使用
---@field RequiresHandle Bool 需要 Handle
---@field ToolTip String 提示文本
---@field Activated Signal<fun()> 工具激活时触发
---@field Deactivated Signal<fun()> 工具停用时触发
---@field Equipped Signal<fun()> 工具装备时触发
---@field Unequipped Signal<fun()> 工具卸下时触发
local Tool = {}

---激活工具
function Tool:Activate() end

---停用工具
function Tool:Deactivate() end

---纯触发区域
---@class TriggerUnit : BasePart
---@field CFrame CFrame 空间变换（位置+旋转）
---@field CanTouch Bool 其他物体碰到此物体时，是否触发此物体的碰撞事件
---@field CollisionGroup String 物体所属的碰撞组名称，用于按碰撞组规则过滤碰撞关系
---@field DisplayModelId String 预览模型
---@field ModelBindParent Bool 启用后，当父节点为 WorldUnit、RenderUnit、TriggerUnit、PhysicsUnit 等支持父子带动的场景单位时，当前单位将整体跟随父节点运动，保持与父节点的相对位置和旋转。运行时可通过脚本设置 .ModelBindParent = true/false 动态切换该行为。
---@field PhysicsActive Bool 是否启用物理模拟，关闭后物体不参与碰撞和物理计算
---@field PhysicsMeshId String 物理资源ID
---@field Scale Vector3 缩放
---@field OnLocalTriggerEnter Signal<fun(info: TriggerCallbackInfo)> 当其他单位进入本触发区域时在本地触发，回调参数为 TriggerCallbackInfo。回调参数：info 触发回调信息
---@field OnLocalTriggerExit Signal<fun(info: TriggerCallbackInfo)> 当其他单位离开本触发区域时在本地触发；若其他单位在离开前被销毁，也会补发该事件。回调参数为 TriggerCallbackInfo。回调参数：info 触发回调信息
---@field OnTriggerEnter Signal<fun(otherUnit: Unit)>
---@field OnTriggerExit Signal<fun(otherUnit: Unit)>
local TriggerUnit = {}

---将物体添加到指定碰撞组，使其遵循该组的碰撞规则
---@param groupName String 要加入的碰撞组名称
function TriggerUnit:AddCollisionWithGroup(groupName) end

---与指定单位建立互不碰撞关系
---@param targetUnit SpaceUnit 要互不碰撞的目标单位
function TriggerUnit:AddNoCollisionPairWithUnit(targetUnit) end

---获取物体当前所属的所有碰撞组名称
---@return String[]
function TriggerUnit:GetCollisionWithGroups() end

---获取当前与此物体互不碰撞的所有单位列表
---@return SpaceUnit[]
function TriggerUnit:GetNoCollisionPairUnitList() end

---清除所有互不碰撞关系，恢复与所有物体的碰撞
function TriggerUnit:RemoveAllNoCollisionPairWithUnit() end

---将物体从指定碰撞组中移除
---@param groupName String 要移除的碰撞组名称
function TriggerUnit:RemoveCollisionWithGroup(groupName) end

---取消与指定单位的互不碰撞关系
---@param targetUnit SpaceUnit 要恢复碰撞的目标单位
function TriggerUnit:RemoveNoCollisionPairWithUnit(targetUnit) end

---Tween 补间动画对象，由 TweenService:Create() 创建，用于驱动目标对象的属性随时间变化
---@class Tween : Unit
---@field Instance Unit 被动画的目标对象
---@field PlaybackState Enums.TweenPlayState 播放状态
---@field Completed Signal<fun(playbackState: Enums.TweenStatus)> 完成事件。回调参数：playbackState 完成状态
local Tween = {}

---取消播放
function Tween:Cancel() end

---暂停播放
function Tween:Pause() end

---开始或恢复播放
function Tween:Play() end

---Unit是所有单位类的基类，可成为游戏对象树的一部分，提供层级管理、属性系统和生命周期等核心能力。
---@class Unit
---@field AssetId String 单位所属的资产预设ID，标识创建时使用的预设资源
---@field Desc String 单位的文字描述信息
---@field Name String 单位的显示名称，可通过 FindFirstChild 等方法按名称查找
---@field Parent Unit 单位在层级树中的父节点，设置后成为该父节点的子节点
---@field AncestryChanged Signal<fun(child: Unit, oldParent: Unit)> 当单位在层级树中的父节点发生变化时触发。回调参数：child 变更的节点, oldParent 原父节点
---@field ChildAdded Signal<fun(child: Unit)> 当新的子节点被添加时触发。回调参数：child 新增的子节点
---@field ChildRemoved Signal<fun(child: Unit)> 当子节点被移除时触发。回调参数：child 移除的子节点
---@field DescendantAdded Signal<fun(descendant: Unit)> 当任意后代节点被添加时触发。回调参数：descendant 新增的后代节点
---@field DescendantRemoving Signal<fun(descendant: Unit)> 当任意后代节点即将被移除时触发。回调参数：descendant 移除的后代节点
---@field Destroying Signal<fun()> 当单位即将被销毁时触发，此时单位仍存在于层级树中
local Unit = {}

---销毁所有子节点
function Unit:ClearAllChildren() end

---创建当前单位的完整副本（包括所有子节点），克隆后的单位无父节点
---@return Unit 克隆后的组件对象
function Unit:Clone() end

---销毁当前单位及其所有子节点，从层级树中移除
function Unit:Destroy() end

---沿父节点链向上查找第一个匹配名称的祖先节点
---@param Name String 要查找的祖先节点名称
---@return Unit 匹配的祖先节点
function Unit:FindFirstAncestor(Name) end

---沿父节点链向上查找第一个精确匹配指定类型的祖先节点
---@param ClassName String 要精确匹配的类型名称
---@return Unit 匹配类的祖先节点
function Unit:FindFirstAncestorOfClass(ClassName) end

---沿父节点链向上查找第一个匹配指定类型或其子类的祖先节点
---@param ClassName String 要匹配的类型名称
---@return Unit 匹配类型的祖先节点
function Unit:FindFirstAncestorWhichIsA(ClassName) end

---在子节点中查找第一个匹配名称的节点，可选择递归查找
---@param Name String 要查找的子节点名称
---@param Recursive? Bool true 时递归搜索所有后代节点
---@return Unit 匹配的子节点
function Unit:FindFirstChild(Name, Recursive) end

---在子节点中查找第一个精确匹配指定类型的节点
---@param ClassName String 要精确匹配的类型名称
---@param Recursive? Bool true 时递归搜索所有后代节点
---@return Unit 匹配类的子节点
function Unit:FindFirstChildOfClass(ClassName, Recursive) end

---在子节点中查找第一个匹配指定类型或其子类的节点
---@param ClassName String 要匹配的类型名称
---@param Recursive? Bool true 时递归搜索所有后代节点
---@return Unit 匹配类型的子节点
function Unit:FindFirstChildWhichIsA(ClassName, Recursive) end

---按 '.' 分隔的路径字符串从当前节点出发逐级查找子节点。例：World:FindFromPath('方块-可变形.垂枝直') 从 World 出发找到垂枝直
---@param path String 以 '.' 分隔的层级路径，如 '父节点.子节点.目标节点'
---@return Unit 查找到的节点，路径不合法或中途断开返回 nil
function Unit:FindFromPath(path) end

---收集单位当前所有属性的键值表
---@return Table 所有属性键值表
function Unit:GetAllProps() end

---获取指定自定义属性的值
---@param attrName String 自定义属性的键名
---@return Any 属性值
function Unit:GetAttribute(attrName) end

---获取指定自定义属性变化时触发的信号对象
---@param attrName String 要监听的自定义属性名称
---@return Signal 自定义属性变化信号
function Unit:GetAttributeChangedSignal(attrName) end

---按索引获取指定位置的子节点
---@param Index Int 子节点的索引位置，从 1 开始
---@return Unit 指定索引的子节点
function Unit:GetChildAtIndex(Index) end

---获取直接子节点的数量
---@return Int 子节点数量
function Unit:GetChildCount() end

---获取所有直接子节点
---@return Unit[] 子节点列表
function Unit:GetChildren() end

---返回当次战斗内服务器与客户端一致的调试标识，每次战斗不同。
---@return String 调试标识
function Unit:GetDebugId() end

---获取所有后代节点（递归包含子节点的子节点）
---@return Unit[] 所有后代节点列表
function Unit:GetDescendants() end

---返回节点从层级树根到自身（不含根）的 '.' 分隔路径字符串，可直接用作 FindFromPath 的参数。例：'方块-可变形.垂枝直'
---@return String 完整路径字符串（'.'分隔）
function Unit:GetFullPath() end

---获取指定属性变化时触发的信号对象，用于监听属性变更
---@param propName String 要监听的属性名称
---@return Signal 属性变化信号
function Unit:GetPropertyChangedSignal(propName) end

---判断当前单位是否拥有子节点
---@return Bool 是否有子节点
function Unit:HasChildren() end

---判断单位是否为指定类型或其子类
---@param className String 要判断的类型名称
---@return Bool 是否为指定类型
function Unit:IsA(className) end

---判断当前单位是否为指定节点的祖先
---@param Descendant Unit 要判断的后代节点
---@return Bool 是否为指定节点的祖先
function Unit:IsAncestorOf(Descendant) end

---判断当前单位是否为指定节点的后代
---@param Ancestor Unit 要判断的祖先节点
---@return Bool 是否为指定节点的后代
function Unit:IsDescendantOf(Ancestor) end

---设置一个自定义属性的值，值变更后会触发属性变化信号
---@param attrName String 自定义属性的键名
---@param value Any 自定义属性的值，支持任意类型
function Unit:SetAttribute(attrName, value) end

---路径点运动器
---@class WaypointMotorUnit : BaseMotorUnit
local WaypointMotorUnit = {}

---焊接约束
---@class WeldConstraint : Unit
---@field ConnectUnitList BasePart[] 服务端创建 WeldConstraint 的构造参数：SpaceUnit 或其继承类的列表。仅服务端初始化使用；单元对象无法序列化跨网络，客户端仍通过 ConnectUnitIdDict 同步接收。
---@field Enabled Bool 用户持久意图（默认 true）。false 时行为等同本约束被销毁：所属装配体移除该组件（按剩余约束拆分，最后一个约束时销毁整个装配体）；true 时若自身+所有连接单元都在 World 下则重新接入。真实生效状态以只读 Active 为准。
---@field ExpectRootUnit BasePart 服务端创建 WeldConstraint 的构造参数：期望作为装配体 Root 的 SpaceUnit。仅服务端初始化使用；客户端仍通过 RootUnitId 同步接收。
local WeldConstraint = {}

---返回该 WeldConstraint 所属装配体的 RootUnit
---@return BasePart
function WeldConstraint:GetRootUnit() end

---处理物理模拟和3D空间查询的基类，预期为任何用于处理3D空间查询和模拟的实例提供API，例如World
---@class WorldRoot : ModelUnit
local WorldRoot = {}

---WorldUnit是一种3D空间的物理组件，同时带有碰撞与渲染表现
---@class WorldUnit : BasePart
---@field AngularDamping Float 角速度的阻尼系数，值越大旋转减速越快，仅对动态(Dynamic)物体生效
---@field AngularVelocity Vector3 物体的初始角速度，仅对动态(Dynamic)物体生效
---@field BodyType Int 物体的物理运动类型：静态(Static)不可修改，运动学(Kinematic)仅通过脚本逻辑驱动，动态(Dynamic)参与完整物理模拟
---@field CanCollide Bool 是否参与物理碰撞，关闭后物体将穿透其他物体
---@field CanQuery Bool 是否参与空间射线检测（Raycast、Spherecast 等），关闭后射线将穿透此物体
---@field CanTouch Bool 其他物体碰到此物体时，是否触发此物体的碰撞事件
---@field CanTrigger Bool 此物体碰到其他物体时，是否触发对方的碰撞事件
---@field CenterOfMass Vector3 物体在局部空间中的质心偏移位置
---@field Climbable Bool 玩家角色是否可以攀爬此物体，仅对静态(Static)物体生效
---@field CollisionGroup String 物体所属的碰撞组名称，用于按碰撞组规则过滤碰撞关系
---@field CustomPhysicalProperties PhysicalProperties 自定义物理材质参数（摩擦力、弹性、密度等），为空时使用默认值
---@field CustomThrownAngle Float 自定义的投掷角度，正值向上抛，负值向下抛
---@field CustomThrownForce Float 自定义的投掷力度
---@field GravityEnabled Bool 是否受重力影响，仅对动态(Dynamic)物体生效
---@field IndividualGravityValue Vector3 自定义重力的方向和大小，默认为 (0, -9.8, 0)
---@field Liftable Bool 玩家角色是否可以抓举此物体，仅对动态(Dynamic)物体生效
---@field LinearDamping Float 线速度的阻尼系数，值越大减速越快，仅对动态(Dynamic)物体生效
---@field LinearVelocity Vector3 物体的初始线速度，仅对动态(Dynamic)物体生效
---@field LocalTransparencyModifier Float 本地透明度乘数
---@field Mass Float 物体的质量，仅对动态(Dynamic)物体生效
---@field Massless Bool 启用后此物体的质量不计入父级装配体的总质量
---@field ModelBindParent Bool 启用后，当父节点为 WorldUnit、RenderUnit、TriggerUnit、PhysicsUnit 等支持父子带动的场景单位时，当前单位将整体跟随父节点运动，保持与父节点的相对位置和旋转。运行时可通过脚本设置 .ModelBindParent = true/false 动态切换该行为。
---@field PhysicsActive Bool 是否启用物理模拟，关闭后物体不参与碰撞和物理计算
---@field PhysicsMeshId String 物理网格资源ID。缺省时，若初始创建时传入了 RenderMeshId，则默认使用该 RenderMeshId 作为物理资源；后续修改 .RenderMeshId 不会影响 PhysicsMeshId
---@field RenderMeshId String 模型的资源路径，用于指定渲染使用的网格资源；启用自定义外观后该属性不生效
---@field TransparentRenderBias Int 控制半透明物体的渲染层级偏置，值越小越先渲染。仅影响半透明物体，不透明物体不受此偏置影响。取值范围 [-15, 16]，超出会被截断到边界。注意：仅当遮挡规则(OcclusionType)为 组件半透明/镜头前推/玩家虚影 时生效；为 不处理 时本偏置不生效
---@field UseCustomThrownAngle Bool 启用后使用自定义的投掷角度替代默认投掷角度
---@field UseCustomThrownForce Bool 启用后使用自定义的投掷力替代默认投掷力
---@field UseIndividualGravity Bool 启用后使用自定义的重力方向和大小替代全局重力
---@field OnCollisionEnter Signal<fun(otherUnit: Unit)> 当其他物体开始与此物体发生碰撞时触发。回调参数：otherUnit 与之发生碰撞的另一个物体
---@field OnCollisionExit Signal<fun(otherUnit: Unit)> 当其他物体与此物体结束碰撞时触发。回调参数：otherUnit 结束碰撞的另一个物体
---@field OnLiftedBegin Signal<fun()> 当此物体被玩家抓举起来时触发
---@field OnLiftedEnd Signal<fun()> 当此物体被玩家放下或投掷后触发
---@field OnLocalCollisionEnter Signal<fun(info: CollisionCallbackInfo)> 当其他物体开始与此物体发生碰撞时在本地触发，回调参数为 CollisionCallbackInfo。回调参数：info 碰撞回调信息
---@field OnLocalCollisionExit Signal<fun(info: CollisionCallbackInfo)> 当其他物体与此物体结束碰撞时在本地触发；若碰撞对方在结束碰撞前被销毁，也会补发该事件。回调参数为 CollisionCallbackInfo。回调参数：info 碰撞回调信息
local WorldUnit = {}

---将物体添加到指定碰撞组，使其遵循该组的碰撞规则
---@param groupName String 要加入的碰撞组名称
function WorldUnit:AddCollisionWithGroup(groupName) end

---与指定单位建立互不碰撞关系
---@param targetUnit SpaceUnit 要互不碰撞的目标单位
function WorldUnit:AddNoCollisionPairWithUnit(targetUnit) end

---在局部空间的指定位置施加一个持续的力
---@param force Vector3 世界空间中的力向量
---@param localPosition Vector3 物体局部空间中的施力点坐标
function WorldUnit:ApplyForceAtLocalPosition(force, localPosition) end

---在世界空间的指定位置施加一个持续的力
---@param force Vector3 世界空间中的力向量
---@param worldPosition Vector3 世界空间中的施力点坐标
function WorldUnit:ApplyForceAtWorldPosition(force, worldPosition) end

---在质心位置施加一个持续的力
---@param force Vector3 世界空间中的力向量
function WorldUnit:ApplyForceToCenterOfMass(force) end

---在质心位置施加一个瞬时冲量
---@param impulse Vector3 冲量向量，方向和大小决定瞬时速度变化
function WorldUnit:ApplyImpulse(impulse) end

---在局部空间的指定位置施加一个瞬时冲量
---@param impulse Vector3 冲量向量
---@param localPosition Vector3 物体局部空间中的冲量施加点坐标
function WorldUnit:ApplyImpulseAtLocalPosition(impulse, localPosition) end

---在世界空间的指定位置施加一个瞬时冲量
---@param impulse Vector3 冲量向量
---@param worldPosition Vector3 世界空间中的冲量施加点坐标
function WorldUnit:ApplyImpulseAtWorldPosition(impulse, worldPosition) end

---对物体施加一个持续的力矩（旋转力）
---@param torque Vector3 各轴方向的力矩大小
function WorldUnit:ApplyTorque(torque) end

---获取物体当前所属的所有碰撞组名称
---@return String[]
function WorldUnit:GetCollisionWithGroups() end

---获取当前与此物体互不碰撞的所有单位列表
---@return SpaceUnit[]
function WorldUnit:GetNoCollisionPairUnitList() end

---获取物体在指定世界坐标位置处的线速度
---@param position Vector3 要查询速度的世界空间坐标点
---@return Vector3
function WorldUnit:GetVelocityAtPosition(position) end

---清除所有互不碰撞关系，恢复与所有物体的碰撞
function WorldUnit:RemoveAllNoCollisionPairWithUnit() end

---将物体从指定碰撞组中移除
---@param groupName String 要移除的碰撞组名称
function WorldUnit:RemoveCollisionWithGroup(groupName) end

---取消与指定单位的互不碰撞关系
---@param targetUnit SpaceUnit 要恢复碰撞的目标单位
function WorldUnit:RemoveNoCollisionPairWithUnit(targetUnit) end

---切换 RenderMeshId 并自动应用新模型的默认皮肤：默认皮肤 >1 个时进入多槽位模式（逐 Submesh 一个默认皮并回填默认染色），单个/无默认皮肤时回到单皮肤模式并写入默认 SkinId（含默认染色回填）。双端可调用，服务端权威（客户端仅本机生效）；自定义外观开启期间不可用
---@param renderMeshId String 模型资源ID
function WorldUnit:SetRenderMeshWithDefaultSkin(renderMeshId) end

---全局Game对象单例。
---@type Game
game = nil

