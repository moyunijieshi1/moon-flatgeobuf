# Moon FlatGeobuf 终审说明与复现


当前公开发布版本：**0.2.1**。本版源代码提交 `76b35ec`，
[完整 CI 通过](https://github.com/moyunijieshi1/moon-flatgeobuf/actions/runs/40302245022)，
四个后端各 35 项测试通过；公共包源独立安装验证见 [发布记录](REGISTRY_RELEASE.md)。

核对日期：2026-10-26。项目：https://github.com/moyunijieshi1/moon-flatgeobuf 。
包：https://mooncakes.io/docs/moyunijieshi1/moon-flatgeobuf 。

## 解决的问题与交付边界

MoonBit 应用需要交换标准地理数据文件，或从远端地图文件按范围读取数据。
本库实现 FlatGeobuf 的二进制编解码、packed R-tree 索引、增量流处理、
GeoJSON 转换和 HTTP Range 查询状态机。文件系统与网络请求由可选 Node.js
适配器执行；核心逻辑不是对官方 JavaScript 库的封装。官方库只用于开发测试。

当前交付是格式 3.0.1 的七类二维线性几何配置，包含混合、嵌套和空集合，
以及 15 种属性类型。**它还不是全格式兼容实现**：曲线、高维向量、逐要素
schema 及部分空几何仍未实现。最终 1.0 目标及未完成项见
[版本兼容矩阵](../COMPATIBILITY.md)，该长期目标不能作为本版已完成能力。
如果评审要求申报中的最终 1.0 目标在本期全部完成，这仍是交付缺口，不能用
二维测试结果代替相应实现和独立验收。

## 从干净环境复现

安装官方 MoonBit 工具链、Node.js 24 和 Python 3，在仓库根目录执行：

```sh
moon version
moon fmt --check
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
moon run examples/basic --target js
npm ci --ignore-scripts
node scripts/check-baseline.cjs
node scripts/interop.cjs
npm run test:host
npm run demo:real-data
node scripts/malformed.cjs
python scripts/count-lines.py
```

Windows 原生后端需要本机 C 工具链；GitHub CI 在 Linux 上执行四个后端的
检查、构建和测试。首次安装工具链及 npm 依赖需要联网，真实数据测试本身
使用仓库中的固定快照，不在运行时下载可变数据。CI 保存 `real-data-evidence`
附件，内含生成的 `.fgb`、区域 GeoJSON 和完整 JSON 报告。

## 三个可展示的工作流

### 1. 本地文件交换与校验

```sh
node scripts/cli.cjs encode fixtures/natural-earth/countries.geojson demo.fgb
node scripts/cli.cjs inspect demo.fgb
node scripts/cli.cjs validate demo.fgb
node scripts/cli.cjs decode demo.fgb restored.geojson
```

输出包含 177 个 Polygon/MultiPolygon 要素。测试逐一比较所有几何坐标及非空
属性值，并执行“本库写出→官方库读入”和“官方库写出→本库读入”；没有只核对
要素数量。空属性按格式约定映射为缺失值。CLI 拒绝覆盖已有输出文件，重复演示
时请换用新文件名。

### 2. 离线区域提取

```sh
node scripts/cli.cjs query demo.fgb 10 45 15 50 selected.geojson
```

该窗口返回 9 个包围盒候选。真实数据测试检查 36 个窗口，含空结果、全球范围、
边界点及固定种子生成的窗口。每个窗口同时比较本库索引查询、本库无索引查询、
官方索引查询与直接遍历原始 GeoJSON 得到的包围盒集合，总计 108 次查询对照。
库 API 另外提供 `Selection` 和 `Predicate`，支持属性过滤、字段投影与分页。

### 3. 远端按需读取

运行 `npm run demo:real-data` 会启动真实本地 HTTP 服务，提供准确 Range、
强 ETag 和 Content-Range，执行区域读取后检查几何、属性及服务端发送字节数。
这验证了真实网络适配流程；它不是公网对象存储部署或外部用户使用证明。

| 指标 | 本次实测 |
| --- | ---: |
| 原始 GeoJSON | 838,726 字节 |
| 带索引 FlatGeobuf | 548,784 字节 |
| 区域 HTTP 响应体合计 | 61,616 字节 |
| HTTP 请求数 | 27 |
| 返回候选 | 9 |
| 相比完整 `.fgb` 少传输的响应体 | 88.77% |

这是指定数据和窗口的传输量对照，不含 HTTP 头，不代表所有窗口的节省比例，
也不证明速度优于官方库。数据、查询及完整结果见
[source.json](../fixtures/natural-earth/source.json) 和 [实测记录](real-data-results.json)。

## 本次加强的工程能力

- `Reader::validate` 改为逐要素校验，不保留全部解码对象，不重复解码每个要素，
  并在成功及失败时保留调用者游标。原始文件 Bytes 和索引仍驻内存，不能称为
  常量总内存校验；完整文件流处理使用单独的 StreamDecoder API。
- 网络适配器支持外部 AbortSignal，视窗改变时可取消旧请求和在途响应体；
  超时、错误长度及不支持的编码会被拒绝并清理响应体。
- 新增真实套接字取消/超时测试、错误响应清理测试，以及单遍校验的回归测试。
- 真实地图数据固定来源提交和 SHA-256，CI 离线校验数据完整性并保存结果。

## 验收证据与限制

| 检查项 | 证据入口 |
| --- | --- |
| 主要实现为 MoonBit | 根目录 `.mbt`；[计数定义](../scripts/count-lines.py)，不把测试、数据、生成文件计作实现 |
| 连续开发历史 | GitHub commits 与 CHANGELOG，不以次数代替功能 |
| 安装、使用、最小示例 | README、examples/basic、Mooncakes 包 |
| 检查、构建、测试及可复现演示 | .github/workflows/ci.yml |
| 格式互操作与错误输入 | 42 项既有对照、真实数据对照、3226 个损坏输入审计用例 |
| 开源及数据来源 | BSD-2-Clause、THIRD_PARTY.md、固定格式快照和数据来源清单 |

地图渲染、坐标投影、精确拓扑相交不属于本库。包围盒候选可能包含假阳性，
尤其是跨日期变更线或跨度很大的几何。部分远端查询不能证明未访问索引分支
正确；对不可信本地文件需先完整校验。偏移和资源限制见 SUPPORTED_FORMAT.md。

## 参赛者应能说明的实现问题

1. **为什么不用 JSON 全文件加载？** FlatGeobuf 的固定索引和要素偏移支持按范围
   定位记录；本次实测显示可少读响应体，但小文件和大范围查询未必有收益。
2. **MoonBit 实现了什么？** FlatBuffers 读写、模式和属性检查、几何、索引遍历、
   查询状态与响应校验；Node.js 只负责 I/O，并没有代替这些核心实现。
3. **为什么固定多个版本号？** 格式基线是 3.0.1，schema 固定至具体提交，
   官方 JS 4.4.0 是对照实现版本；不能混为一个版本，也不能据此宣称全格式兼容。
4. **为什么需要 ETag？** 分段读取必须来自同一个对象版本。后续请求发送
   If-Match；对象变动时拒绝继续拼接，防止把不同版本的字节混在一起。
5. **测试如何避免自证正确？** 对照官方实现、原始 GeoJSON 全扫描和服务端计数，
   另测损坏数据及异常网络。尚未测试的曲线和高维能力明确列为未完成。

## 官方标准来源

2026-10-26 核对[赛事官网](https://moonbitlang.github.io/Hackathon2026/)及其
[公开页面源码](https://github.com/moonbitlang/Hackathon2026/blob/main/src/App.tsx)：
十月报名及验收截止日为 10 月 31 日；要求可运行的代码、README、测试和演示，
并强调实质工作、开源来源及参赛者对 AI 辅助成果的理解。
官网链接的飞书正式章程当前无法由本次检索工具读取，本说明不代替赛事通知。
是否已加入赛事群、群昵称及终审表单提交状态需参赛者本人确认。
