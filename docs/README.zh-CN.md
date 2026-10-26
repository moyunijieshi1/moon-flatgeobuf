# Moon FlatGeobuf

这个库让 MoonBit 项目直接读取、写出标准 `.fgb` 地理数据，并按地图范围
查询要素。应用可以从本地文件提取一个区域，也可以通过 HTTP Range 从远端
文件中读取相关索引和要素，供地图展示、区域分析或数据发布使用。

文件格式基线固定为 FlatGeobuf **3.0.1**，参考 schema 固定到官方提交
`3df4db1a9551821f66a1d789bb8632c8076926be`。官方 JS 对照库的版本 **4.4.0**
是实现版本，不能当成格式版本。当前 0.2.1 已支持七类二维线性几何，包含
混合、嵌套和空 GeometryCollection；这仍是有明确边界的配置子集，不是完整
格式互操作。完整兼容的最终范围、待完成项和逐项验收门槛见 COMPATIBILITY.md。

它提供的是格式层和查询层，不负责地图绘制和坐标投影。社区现有的 Shapefile、
几何算法和空间索引包可以与它配合使用。

## 使用

安装：`moon add moyunijieshi1/moon-flatgeobuf`。完整示例执行：
`moon run examples/basic --target js`。具体 API 和 CLI 命令见根目录 README。

主要入口：

- `Reader::open`、`next`、`read_all`、`at`、`query`：完整文件和范围读取。
- `write_dataset`：写出带索引或不带索引的文件。
- `import_geojson`：推断可支持的模式并导入 GeoJSON。
- `dataset_from_geojson`：使用调用者提供的显式模式导入。
- `Selection`、`Predicate`、`Reader::select`：属性过滤、字段投影和分页。
- `StreamDecoder`、`StreamWriter`：分块读取和未知总数的无索引流式输出。
- `RangeQuery`：由宿主执行请求的 HTTP 按需读取状态机。
- `inspect_archive`、`audit_archive`：数据统计和结构诊断。

远端服务器必须返回准确的 206 和 Content-Range，并提供稳定的强 ETag。
索引查询得到的是包围盒相交候选，不等同于精确的多边形相交结果。支持范围、
内存上限、空几何和大整数说明见 SUPPORTED_FORMAT.md。

测试包含独立官方 JS 实现的双向读写对照、索引与全扫描结果对照、真实本地
HTTP 服务验收、任意分块的流式读取以及损坏文件诊断。测试命令见根 README。

终审复现入口见 [终审说明](FINAL_REVIEW.zh-CN.md)。运行 `npm run demo:real-data`
可离线验证 177 个真实地图要素、36 个查询窗口，并生成区域提取文件和传输量报告。
网络适配器支持 `AbortSignal`，视窗改变时可以取消旧请求，包含正在读取的响应体。
