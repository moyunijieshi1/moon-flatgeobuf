# Moon FlatGeobuf 1.0.0

使用 MoonBit 读写固定 FlatGeobuf 3.0.1 二进制 schema。原生接口保留 15 种
具体几何类型、Z/M/T/TM、逐要素 schema 和空几何。二维 GeoJSON 转换仍有
独立边界。支持内容、核验方法与未承诺事项见[兼容矩阵](../COMPATIBILITY.md)。

- 安装：`moon add moyunijieshi1/moon-flatgeobuf@1.0.0`
- 曲线与时间坐标示例：`moon run examples/native --target js`
- 二维 GeoJSON 示例：`moon run examples/basic --target js`
- 原生筛选：`node scripts/cli.cjs query-native input.fgb 115 38 118 41 selected.fgb`
  （先执行 `moon build --target js`）
- 原生远端：`remote-native` 输出保留原生字段的 FGB。服务端需支持 206、
  Content-Range 和稳定强 ETag。

`NativeReader`、`write_native_dataset`、`NativeStreamDecoder`、
`NativeStreamWriter` 和 `NativeRangeQuery` 是二进制数据入口。
对需要保存曲线、高维坐标或逐要素字段的文件，不应先转 GeoJSON。
包围盒筛选只返回候选；不提供精确拓扑求交、重投影或渲染。

CI 执行四个 MoonBit 后端的检查、构建和测试。GDAL 3.11.5 验证曲线、曲面、
Z/M 和空要素场景；固定的官方 FlatBuffers 类对照覆盖 T/TM 和逐要素 schema。
[英文 README](../README.md) 提供可运行步骤。[0.2.1 历史终审材料](FINAL_REVIEW.zh-CN.md)
只记录旧版，不作为 1.0.0 的验收依据。
