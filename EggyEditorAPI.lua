-- EggyEditorAPI: 编辑器编辑时API
-- Auto-generated, do not edit

---@class Other

Other = {}

---获取所有EUI节点ID
---@return List 节点ID列表
function EditorAPI.get_all_eui_node_ids() end

---按名称查询EUI节点
---@param name Str 节点名称
---@return List EUI节点ID列表
function EditorAPI.get_eui_node_ids_by_name(name) end

---获取EUI节点子节点列表
---@param node_id ENode 节点ID
---@return List 子节点ID列表
function EditorAPI.get_eui_node_children(node_id) end

---获取EUI节点父节点ID
---@param node_id ENode 节点ID
---@return ENode 父节点ID
function EditorAPI.get_eui_node_parent(node_id) end

---获取EUI节点类型
---@param node_id ENode 节点ID
---@return Str 节点类型字符串
function EditorAPI.get_eui_node_type(node_id) end

---获取EUI节点属性
---@param node_id ENode 节点ID
---@param attr_name Str 属性名
---@return ETypeMeta 属性值
function EditorAPI.get_eui_node_attr(node_id, attr_name) end

---创建EUI节点（通用）
---@param node_type Str 节点类型
---@param name Str 节点名称
---@param parent_id ENode 父节点ID
---@return ENode 节点ID
function EditorAPI.create_eui_node(node_type, name, parent_id) end

---通过预设创建EUI节点
---@param prefab_id Int 预设ID
---@param parent_id ENode 父节点ID
---@return ENode 根节点ID
function EditorAPI.create_eui_node_from_prefab(prefab_id, parent_id) end

---创建EUI 3D Layer节点
---@param parent_id ENode 父节点ID
---@return ENode 节点ID
function EditorAPI.create_eui_3d_layer_node(parent_id) end

---设置EUI节点属性（通用）
---@param node_id ENode 节点ID
---@param attr_name Str 属性名
---@param value ETypeMeta 属性值
---@return Bool 是否成功
function EditorAPI.set_eui_node_attr(node_id, attr_name, value) end

---批量设置EUI节点属性
---@param node_id ENode 节点ID
---@param attr_dict Dict 属性字典
---@return Bool 是否成功
function EditorAPI.set_eui_node_attrs(node_id, attr_dict) end

---设置EUI节点父节点
---@param node_id ENode 节点ID
---@param new_parent_id ENode 目标父节点ID
---@return Bool 是否成功
function EditorAPI.set_eui_node_parent(node_id, new_parent_id) end

---设置EUI节点同级顺序
---@param node_id ENode 节点ID
---@param index Int 目标索引
---@return Bool 是否成功
function EditorAPI.set_eui_node_sibling_index(node_id, index) end

---删除EUI节点
---@param node_id ENode 节点ID
---@return Bool 是否成功
function EditorAPI.destroy_eui_node(node_id) end

---创建EUI图片节点
---@param preset_id Int 预设ID
---@param parent_id ENode 父节点ID
---@param x Fixed X坐标
---@param y Fixed Y坐标
---@param width Fixed 宽度
---@param height Fixed 高度
---@param name Str 节点名称
---@return EImage 节点ID
function EditorAPI.create_eui_image_node(preset_id, parent_id, x, y, width, height, name) end

---创建EUI文本节点
---@param parent_id ENode 父节点ID
---@param x Fixed X坐标
---@param y Fixed Y坐标
---@param width Fixed 宽度
---@param height Fixed 高度
---@param name Str 节点名称
---@param text Str 文本内容
---@return ELabel 节点ID
function EditorAPI.create_eui_label_node(parent_id, x, y, width, height, name, text) end

---创建EUI按钮节点
---@param preset_id Int 预设ID
---@param parent_id ENode 父节点ID
---@param x Fixed X坐标
---@param y Fixed Y坐标
---@param width Fixed 宽度
---@param height Fixed 高度
---@param name Str 节点名称
---@return EButton 节点ID
function EditorAPI.create_eui_button_node(preset_id, parent_id, x, y, width, height, name) end

---创建EUI进度条节点
---@param preset_id Int 预设ID
---@param parent_id ENode 父节点ID
---@param x Fixed X坐标
---@param y Fixed Y坐标
---@param width Fixed 宽度
---@param height Fixed 高度
---@param name Str 节点名称
---@return EProgressbar 节点ID
function EditorAPI.create_eui_progressbar_node(preset_id, parent_id, x, y, width, height, name) end

---创建EUI输入框节点
---@param parent_id ENode 父节点ID
---@param x Fixed X坐标
---@param y Fixed Y坐标
---@param width Fixed 宽度
---@param height Fixed 高度
---@param name Str 节点名称
---@param text Str 默认文本
---@return EInputField 节点ID
function EditorAPI.create_eui_input_node(parent_id, x, y, width, height, name, text) end

---创建EUI列表节点
---@param parent_id ENode 父节点ID
---@param x Fixed X坐标
---@param y Fixed Y坐标
---@param width Fixed 宽度
---@param height Fixed 高度
---@param name Str 节点名称
---@return ENode 节点ID
function EditorAPI.create_eui_listview_node(parent_id, x, y, width, height, name) end

---创建EUI遮罩节点
---@param parent_id ENode 父节点ID
---@param x Fixed X坐标
---@param y Fixed Y坐标
---@param width Fixed 宽度
---@param height Fixed 高度
---@param name Str 节点名称
---@param clipping_id Int 蒙版图片ID
---@return ENode 节点ID
function EditorAPI.create_eui_clipping_node(parent_id, x, y, width, height, name, clipping_id) end

---创建EUI动效节点
---@param preset_id Int 预设ID
---@param parent_id ENode 父节点ID
---@param x Fixed X坐标
---@param y Fixed Y坐标
---@param width Fixed 宽度
---@param height Fixed 高度
---@param name Str 节点名称
---@return ENode 节点ID
function EditorAPI.create_eui_animation_node(preset_id, parent_id, x, y, width, height, name) end

---创建EUI画布层节点
---@param name Str 节点名称
---@param parent_id ECanvas 父节点ID
---@return ECanvas 节点ID
function EditorAPI.create_eui_canvas_layer_node(name, parent_id) end

---设置EUI节点位置
---@param node_id ENode 节点ID
---@param x Fixed x坐标
---@param y Fixed y坐标
---@return Bool 是否成功
function EditorAPI.set_eui_node_pos(node_id, x, y) end

---设置EUI节点尺寸
---@param node_id ENode 节点ID
---@param width Fixed 宽度
---@param height Fixed 高度
---@return Bool 是否成功
function EditorAPI.set_eui_node_size(node_id, width, height) end

---设置EUI节点编辑器可见性
---@param node_id ENode 节点ID
---@param visible Bool 是否可见
---@return Bool 是否成功
function EditorAPI.set_eui_node_visible(node_id, visible) end

---设置EUI节点透明度
---@param node_id ENode 节点ID
---@param opacity Fixed 透明度0~1
---@return Bool 是否成功
function EditorAPI.set_eui_node_opacity(node_id, opacity) end

---设置EUI节点名称
---@param node_id ENode 节点ID
---@param name Str 节点名称
---@return Bool 是否成功
function EditorAPI.set_eui_node_name(node_id, name) end

---设置EUI图片节点贴图
---@param node_id EImage 节点ID
---@param texture_path Str 图片资源路径
---@return Bool 是否成功
function EditorAPI.set_eui_image_texture(node_id, texture_path) end

---设置EUI图片节点颜色
---@param node_id EImage 节点ID
---@param r Int R
---@param g Int G
---@param b Int B
---@param a Int A
---@return Bool 是否成功
function EditorAPI.set_eui_image_color(node_id, r, g, b, a) end

---设置EUI文本节点内容
---@param node_id ELabel 节点ID
---@param text Str 文字内容
---@return Bool 是否成功
function EditorAPI.set_eui_label_text(node_id, text) end

---设置EUI文本节点字号
---@param node_id ELabel 节点ID
---@param font_size Int 字号
---@return Bool 是否成功
function EditorAPI.set_eui_label_font_size(node_id, font_size) end

---设置EUI文本节点颜色
---@param node_id ELabel 节点ID
---@param r Int R
---@param g Int G
---@param b Int B
---@param a Int A
---@return Bool 是否成功
function EditorAPI.set_eui_label_color(node_id, r, g, b, a) end

---设置EUI按钮节点文字
---@param node_id EButton 节点ID
---@param text Str 文字内容
---@return Bool 是否成功
function EditorAPI.set_eui_button_text(node_id, text) end

---设置EUI按钮节点常态图片
---@param node_id EButton 节点ID
---@param texture_path Str 图片资源路径
---@return Bool 是否成功
function EditorAPI.set_eui_button_normal_image(node_id, texture_path) end

---设置EUI按钮节点启用状态
---@param node_id EButton 节点ID
---@param enabled Bool 是否启用
---@return Bool 是否成功
function EditorAPI.set_eui_button_enabled(node_id, enabled) end

---设置EUI进度条当前值
---@param node_id EProgressbar 节点ID
---@param value Int 当前进度值
---@return Bool 是否成功
function EditorAPI.set_eui_progressbar_value(node_id, value) end

---设置EUI进度条最大值
---@param node_id EProgressbar 节点ID
---@param max_value Int 最大进度值
---@return Bool 是否成功
function EditorAPI.set_eui_progressbar_max(node_id, max_value) end

---设置EUI进度条最小值
---@param node_id EProgressbar 节点ID
---@param min_value Int 最小进度值
---@return Bool 是否成功
function EditorAPI.set_eui_progressbar_min(node_id, min_value) end

---设置EUI进度条过渡进度
---@param node_id EProgressbar 节点ID
---@param value Int 目标进度值
---@param duration Fixed 过渡时间(秒)
---@return Bool 是否成功
function EditorAPI.set_eui_progressbar_transition(node_id, value, duration) end

---设置EUI按钮节点按下图片
---@param node_id EButton 节点ID
---@param texture_path Str 图片资源路径
---@return Bool 是否成功
function EditorAPI.set_eui_button_pressed_image(node_id, texture_path) end

---设置EUI按钮节点文字颜色
---@param node_id EButton 节点ID
---@param r Int R
---@param g Int G
---@param b Int B
---@param a Int A
---@return Bool 是否成功
function EditorAPI.set_eui_button_text_color(node_id, r, g, b, a) end

---设置EUI按钮节点文字字号
---@param node_id EButton 节点ID
---@param font_size Int 字号
---@return Bool 是否成功
function EditorAPI.set_eui_button_font_size(node_id, font_size) end

---设置EUI文本节点字体
---@param node_id ELabel 节点ID
---@param font_key Str 字体路径
---@return Bool 是否成功
function EditorAPI.set_eui_label_font(node_id, font_key) end

---设置EUI文本节点背景颜色
---@param node_id ELabel 节点ID
---@param r Int R
---@param g Int G
---@param b Int B
---@param a Int A
---@return Bool 是否成功
function EditorAPI.set_eui_label_background_color(node_id, r, g, b, a) end

---设置EUI文本节点背景不透明度
---@param node_id ELabel 节点ID
---@param opacity Fixed 不透明度0~1
---@return Bool 是否成功
function EditorAPI.set_eui_label_background_opacity(node_id, opacity) end

---设置EUI文本节点描边开关
---@param node_id ELabel 节点ID
---@param enabled Bool 是否开启
---@return Bool 是否成功
function EditorAPI.set_eui_label_outline_enabled(node_id, enabled) end

---设置EUI文本节点描边颜色
---@param node_id ELabel 节点ID
---@param r Int R
---@param g Int G
---@param b Int B
---@param a Int A
---@return Bool 是否成功
function EditorAPI.set_eui_label_outline_color(node_id, r, g, b, a) end

---设置EUI文本节点描边宽度
---@param node_id ELabel 节点ID
---@param width Fixed 描边宽度
---@return Bool 是否成功
function EditorAPI.set_eui_label_outline_width(node_id, width) end

---设置EUI文本节点描边不透明度
---@param node_id ELabel 节点ID
---@param opacity Fixed 不透明度0~1
---@return Bool 是否成功
function EditorAPI.set_eui_label_outline_opacity(node_id, opacity) end

---设置EUI文本节点阴影开关
---@param node_id ELabel 节点ID
---@param enabled Bool 是否开启
---@return Bool 是否成功
function EditorAPI.set_eui_label_shadow_enabled(node_id, enabled) end

---设置EUI文本节点阴影颜色
---@param node_id ELabel 节点ID
---@param r Int R
---@param g Int G
---@param b Int B
---@param a Int A
---@return Bool 是否成功
function EditorAPI.set_eui_label_shadow_color(node_id, r, g, b, a) end

---设置EUI文本节点阴影X偏移
---@param node_id ELabel 节点ID
---@param x_offset Fixed X偏移
---@return Bool 是否成功
function EditorAPI.set_eui_label_shadow_x_offset(node_id, x_offset) end

---设置EUI文本节点阴影Y偏移
---@param node_id ELabel 节点ID
---@param y_offset Fixed Y偏移
---@return Bool 是否成功
function EditorAPI.set_eui_label_shadow_y_offset(node_id, y_offset) end

---设置EUI节点交互开关
---@param node_id ENode 节点ID
---@param enabled Bool 是否可交互
---@return Bool 是否成功
function EditorAPI.set_eui_node_touch_enabled(node_id, enabled) end

---设置EUI节点可见性
---@param node_id ENode 节点ID
---@param visible Bool 是否可见
---@return Bool 是否成功
function EditorAPI.set_eui_node_canvas_visible(node_id, visible) end

---修改EUI 3D Layer预设属性
---@param node_id ENode 3D Layer节点ID
---@param key Str 属性名
---@param value ETypeMeta 属性值
---@return Bool 是否成功
function EditorAPI.modify_eui_3d_layer_prefab(node_id, key, value) end

---修改EUI 3D Layer子节点数据
---@param layer_node_id ENode 3D Layer节点ID
---@param child_node_id ENode 子节点ID
---@return Bool 是否成功
function EditorAPI.sync_eui_3d_layer_child(layer_node_id, child_node_id) end

---获取EUI 3D Layer预设数据
---@param node_id ENode 3D Layer节点ID
---@return Dict 预设数据字典
function EditorAPI.get_eui_3d_layer_prefab_data(node_id) end

---设置EUI输入框内容
---@param node_id EInputField 节点ID
---@param text Str 文字内容
---@return Bool 是否成功
function EditorAPI.set_eui_input_field_text(node_id, text) end

---设置EUI输入框占位文字
---@param node_id EInputField 节点ID
---@param placeholder Str 占位文字
---@return Bool 是否成功
function EditorAPI.set_eui_input_field_placeholder(node_id, placeholder) end

---打开UI编辑器
---@return Bool 是否成功
function EditorAPI.open_eui_editor() end

---当前是否处于UI编辑模式
---@return Bool 是否处于UI编辑模式
function EditorAPI.is_in_eui_edit_mode() end

---切换到场景界面预设编辑模式
---@param layer_id ENode 3D Layer节点ID
---@return Bool 是否成功
function EditorAPI.switch_to_3d_layer_edit_mode(layer_id) end

---切换回普通画布编辑模式
---@return Bool 是否成功
function EditorAPI.switch_to_normal_canvas_edit_mode() end

---当前是否处于场景界面编辑模式
---@return Bool 是否处于3D编辑模式
function EditorAPI.is_in_3d_layer_edit_mode() end

---修改地图滤镜
---@param render_color_hue Fixed 色相
---@param render_color_vaule Fixed 明度
---@param render_color_sat Fixed 饱和度
---@param render_color_contrast Fixed 对比度
---@param render_color_amount Fixed 整体偏色程度
---@param render_color_midtones Color 中灰偏色
---@param render_color_midtonespower Fixed 中灰偏色程度
---@param render_color_shodows Color 暗部偏色
---@param render_color_shodowspower Fixed 暗部偏色程度
---@param render_color_hilights Color 亮部偏色
---@param render_color_hilightspower Fixed 亮部偏色程度
function EditorAPI.change_render_color(render_color_hue, render_color_vaule, render_color_sat, render_color_contrast, render_color_amount, render_color_midtones, render_color_midtonespower, render_color_shodows, render_color_shodowspower, render_color_hilights, render_color_hilightspower) end

---获取地图滤镜属性
---@return Dict 属性列表
function EditorAPI.get_render_color_properties() end

---获取编辑器运行时状态全量快照
---@return Dict 状态快照
function EditorAPIRuntimeStates.get_runtime_states_snapshot() end

---获取指定模块的运行时状态
---@param module_name Str 模块名
---@return Dict 模块状态
function EditorAPIRuntimeStates.get_runtime_module_state(module_name) end

---获取运行时状态模块的 Schema 描述
---@return Dict Schema 描述
function EditorAPIRuntimeStates.get_runtime_states_schema() end

---加载脚本模块
---@param name Str 模块名
function EditorAPI.require(name) end

---设置菜单对话框
---@param name Str 入口名称
---@param config Dict 配置描述表
function EditorAPI.set_menu_dialog(name, config) end

---查询场景中的单位
---@param pattern Str 名称
---@param reg_math Bool 启用正则匹配
---@return List 单位信息列表
function EditorAPI.query_scene_units(pattern, reg_math) end

---执行游戏指令
---@param content Str 代码
function EditorAPI.game_execute(content) end

---输出日志
---@param content Str 日志内容
function EditorAPI.log(content) end

---在场景中创建组件
---@param unit_key ObstacleKey 组件编号
---@param pos Point3 坐标
---@param parent_uid Int 父节点ID
---@return UnitID 组件ID
function EditorAPI.create_obstacle(unit_key, pos, parent_uid) end

---删除场景中的组件
---@param unit_id UnitID 组件ID
function EditorAPI.destroy_obstacle(unit_id) end

---在场景中创建组件组
---@param group_key UnitGroupKey 组件组编号
---@param pos Point3 坐标
---@return UnitID 组件组ID
function EditorAPI.create_unit_group(group_key, pos) end

---获取所有单位
---@return ListUnit 单位列表
function EditorAPI.get_all_unit_ids() end

---获取当前被选中单位
---@return ListUnit 单位列表
function EditorAPI.get_selected_unit_ids() end

---查询场景中的单位
---@param pattern Str 名称
---@param reg_math Bool 启用正则匹配
---@return List 单位信息列表
function EditorAPI.query_unit_ids(pattern, reg_math) end

---获取单位组件编号
---@param unit_id UnitID 单位ID
---@return UnitKey 组件编号
function EditorAPI.get_unit_prefab_key(unit_id) end

---设置单位属性
---@param unit_id UnitID 单位ID
---@param attr_key Str 属性名
---@param attr_value ETypeMeta 属性值
function EditorAPI.set_unit_attr(unit_id, attr_key, attr_value) end

---获取单位属性
---@param unit_id UnitID 单位ID
---@param attr_key Str 属性名
---@return ETypeMeta 单位列表
function EditorAPI.get_unit_attr(unit_id, attr_key) end

---获取单位空间信息
---@param unit_id UnitID 单位ID
---@return LuaTable 空间信息数据
function EditorAPI.get_unit_space_info(unit_id) end

---生成随机数
---@param a Fixed 随机范围开始
---@param b Fixed 随机范围结束
---@return Fixed 随机结果
function EditorAPI.random(a, b) end

---获取地图自定义数据
---@param key Str 自定义数据名
---@return LuaTable 存储数据
function EditorAPI.get_custom_map_data(key) end

---设置地图自定义数据
---@param key Str 自定义数据名
---@param value LuaTable 存储数据
function EditorAPI.set_custom_map_data(key, value) end

---移除地图自定义数据
---@param key Str 自定义数据名
function EditorAPI.remove_custom_map_data(key) end

---开始试玩
function EditorAPI.run_game() end

---停止试玩
function EditorAPI.stop_game() end

---获取日志
---@return Str 日志内容
function EditorAPI.get_editor_log() end

---导入组件预设数据
---@param path Str 文件路径
function EditorAPI.input_unit_prefab(path) end

---导出组件预设数据
---@param eid Int 预设ID
---@param path Str 文件路径
function EditorAPI.output_unit_prefab(eid, path) end

---导出组件预设的完整数据
---@param eid Int 预设ID
---@param path Str 文件路径
function EditorAPI.output_unit_prefab_full(eid, path) end

---导入逻辑体预设数据
---@param path Str 文件路径
function EditorAPI.input_trigger_prefab(path) end

---导出逻辑体预设数据
---@param eid Int 预设ID
---@param path Str 文件路径
function EditorAPI.output_trigger_prefab(eid, path) end

---导出逻辑体预设的完整数据
---@param eid Int 预设ID
---@param path Str 文件路径
function EditorAPI.output_trigger_prefab_full(eid, path) end

---导入生物预设数据
---@param path Str 文件路径
function EditorAPI.input_creature_prefab(path) end

---导出生物预设数据
---@param eid Int 预设ID
---@param path Str 文件路径
function EditorAPI.output_creature_prefab(eid, path) end

---导出生物预设的完整数据
---@param eid Int 预设ID
---@param path Str 文件路径
function EditorAPI.output_creature_prefab_full(eid, path) end

---导入蛋仔角色预设数据
---@param path Str 文件路径
function EditorAPI.input_char_prefab(path) end

---导出蛋仔角色预设数据
---@param eid Int 预设ID
---@param path Str 文件路径
function EditorAPI.output_char_prefab(eid, path) end

---导出蛋仔角色预设的完整数据
---@param eid Int 预设ID
---@param path Str 文件路径
function EditorAPI.output_char_prefab_full(eid, path) end

---导入路径点预设数据
---@param path Str 文件路径
function EditorAPI.input_virtual_point_prefab(path) end

---导出路径点预设数据
---@param eid Int 预设ID
---@param path Str 文件路径
function EditorAPI.output_virtual_point_prefab(eid, path) end

---导出路径点预设的完整数据
---@param eid Int 预设ID
---@param path Str 文件路径
function EditorAPI.output_virtual_point_prefab_full(eid, path) end

---导入装饰物预设数据
---@param path Str 文件路径
function EditorAPI.input_decoration_prefab(path) end

---导出装饰物预设数据
---@param eid Int 预设ID
---@param path Str 文件路径
function EditorAPI.output_decoration_prefab(eid, path) end

---导出装饰物预设的完整数据
---@param eid Int 预设ID
---@param path Str 文件路径
function EditorAPI.output_decoration_prefab_full(eid, path) end

---导入组件组预设数据
---@param path Str 文件路径
function EditorAPI.input_group_prefab(path) end

---导出组件组预设数据
---@param eid Int 预设ID
---@param path Str 文件路径
function EditorAPI.output_group_prefab(eid, path) end

---导出组件组预设的完整数据
---@param eid Int 预设ID
---@param path Str 文件路径
function EditorAPI.output_group_prefab_full(eid, path) end

---导入技能预设数据
---@param path Str 文件路径
function EditorAPI.input_ability_prefab(path) end

---导出技能预设数据
---@param eid Int 预设ID
---@param path Str 文件路径
function EditorAPI.output_ability_prefab(eid, path) end

---导出技能预设的完整数据
---@param eid Int 预设ID
---@param path Str 文件路径
function EditorAPI.output_ability_prefab_full(eid, path) end

---导入效果预设数据
---@param path Str 文件路径
function EditorAPI.input_modifier_prefab(path) end

---导出效果预设数据
---@param eid Int 预设ID
---@param path Str 文件路径
function EditorAPI.output_modifier_prefab(eid, path) end

---导出效果预设的完整数据
---@param eid Int 预设ID
---@param path Str 文件路径
function EditorAPI.output_modifier_prefab_full(eid, path) end

---导入物品预设数据
---@param path Str 文件路径
function EditorAPI.input_equipment_prefab(path) end

---导出物品预设数据
---@param eid Int 预设ID
---@param path Str 文件路径
function EditorAPI.output_equipment_prefab(eid, path) end

---导出物品预设的完整数据
---@param eid Int 预设ID
---@param path Str 文件路径
function EditorAPI.output_equipment_prefab_full(eid, path) end

---写入文件
---@param file_path Str 文件路径
---@param content Str 文件内容
function EditorAPI.write_file(file_path, content) end

---延迟调用函数
---@param interval Fixed 间隔时间（秒）
---@param callback Function 回调
function EditorAPI.call_delay_time(interval, callback) end

---获取场景中所有组件的数据
---@return Dict 组件列表
function EditorAPI.get_all_scene_unit_data() end

---获取场景中指定ID的组件的数据
---@param uid Int 组件ID
---@return Dict 组件数据
function EditorAPI.get_scene_unit_data(uid) end

---设置相机属性
---@param kv_data Dict 属性列表
function EditorAPI.set_camera_properties(kv_data) end

---获取相机属性
---@return Dict 属性列表
function EditorAPI.get_camera_properties() end

---设置天空背景
---@param skybox_id Int 天空背景ID
function EditorAPI.set_skybox(skybox_id) end

---获取当前天空背景ID
---@return Int 天空背景ID
function EditorAPI.get_cur_skybox() end

---设置环境光属性
---@param kv_data Dict 属性列表
function EditorAPI.set_skylight_properties(kv_data) end

---获取环境光属性
---@return Dict 属性列表
function EditorAPI.get_skylight_properties() end

---设置雾效属性
---@param kv_data Dict 属性列表
function EditorAPI.set_fog_properties(kv_data) end

---获取雾效属性
---@return Dict 属性列表
function EditorAPI.get_fog_properties() end

---为预设新增属性
---@param prefab_type Str 预设类型
---@param attr_meta Dict 属性定义
function EditorAPI.add_unit_attr_meta(prefab_type, attr_meta) end

---获取关卡触发组key列表
---@return List key触发器组名映射
function EditorAPI.get_global_trigger_group_list() end

---输入关卡触发器
---@param path Str 触发器文件路径
function EditorAPI.input_global_trigger_group(path) end

---输出关卡触发器组
---@param group_id Str 触发器组ID
---@param path Str 导出文件路径
---@return Dict 触发器组数据
function EditorAPI.output_global_trigger_group(group_id, path) end

---新建关卡触发器组
---@param name Str 触发器组名
---@return Str 触发器组ID
function EditorAPI.new_global_trigger_group(name) end

---删除关卡触发器组
---@param group_id Str 触发器组ID
function EditorAPI.delete_global_trigger_group(group_id) end

---获取函数触发组key列表
---@return List key触发器组名映射
function EditorAPI.get_function_trigger_group_list() end

---输入函数触发器
---@param path Str 触发器文件路径
function EditorAPI.input_function_trigger_data(path) end

---输出函数触发器组
---@param func_id Str 函数ID
---@param path Str 导出文件路径
---@return Dict 触发器组数据
function EditorAPI.output_function_trigger_data(func_id, path) end

---新建函数触发器
---@param name Str 函数名
---@return Str 触发器组ID
function EditorAPI.new_function_trigger_data(name) end

---删除函数触发器
---@param group_id Str 函数ID
function EditorAPI.delete_function_trigger_data(group_id) end

---获取组件库触发器组key列表
---@param prefab_eid Int 组件预设ID
function EditorAPI.get_unit_prefab_trigger_group_list(prefab_eid) end

---获取技能库触发器组key列表
---@param prefab_eid Int 技能预设ID
function EditorAPI.get_ability_prefab_trigger_group_list(prefab_eid) end

---获取效果库触发器组key列表
---@param prefab_eid Int 效果预设ID
function EditorAPI.get_modifier_prefab_trigger_group_list(prefab_eid) end

---输入组件库触发器组
---@param prefab_eid Int 组件预设ID
---@param path Str 导入文件路径
function EditorAPI.input_unit_prefab_trigger_group(prefab_eid, path) end

---输出组件库触发器组
---@param prefab_eid Int 组件预设ID
---@param group_id Str 触发器组ID
---@param path Str 导出文件路径
function EditorAPI.output_unit_prefab_trigger_group(prefab_eid, group_id, path) end

---输入技能库触发器组
---@param prefab_eid Int 技能预设ID
---@param path Str 触发器组ID
function EditorAPI.input_ability_prefab_trigger_group(prefab_eid, path) end

---输出技能库触发器组
---@param prefab_eid Int 技能预设ID
---@param group_id Str 触发器组ID
---@param path Str 导出文件路径
function EditorAPI.output_ability_prefab_trigger_group(prefab_eid, group_id, path) end

---输入效果库触发器组
---@param prefab_eid Int 效果预设ID
---@param path Str 触发器组ID
function EditorAPI.input_modifier_prefab_trigger_group(prefab_eid, path) end

---输出效果库触发器组
---@param prefab_eid Int 效果预设ID
---@param group_id Str 触发器组ID
---@param path Str 导出文件路径
function EditorAPI.output_modifier_prefab_trigger_group(prefab_eid, group_id, path) end

---新建组件库触发器组
---@param prefab_eid Int 组件预设ID
---@param group_name Str 触发器组名
---@return Str 触发器组ID
function EditorAPI.new_unit_prefab_trigger_group(prefab_eid, group_name) end

---新建技能库触发器组
---@param prefab_eid Int 技能预设ID
---@param group_name Str 触发器组名
---@return Str 触发器组ID
function EditorAPI.new_ability_prefab_trigger_group(prefab_eid, group_name) end

---新建效果库触发器组
---@param prefab_eid Int 效果预设ID
---@param group_name Str 触发器组名
---@return Str 触发器组ID
function EditorAPI.new_modifier_prefab_trigger_group(prefab_eid, group_name) end

---删除组件库触发器组
---@param prefab_eid Int 组件预设ID
---@param group_id Str 触发器组ID
function EditorAPI.delete_unit_prefab_trigger_group(prefab_eid, group_id) end

---删除技能库触发器组
---@param prefab_eid Int 技能预设ID
---@param group_id Str 触发器组ID
function EditorAPI.delete_ability_prefab_trigger_group(prefab_eid, group_id) end

---删除效果库触发器组
---@param prefab_eid Int 效果预设ID
---@param group_id Str 触发器组ID
function EditorAPI.delete_modifier_prefab_trigger_group(prefab_eid, group_id) end

---新建剧情文件
---@param desc Str 剧情文件名
---@param duration Fixed 剧情时长
---@return Str 剧情id
function EditorAPI.new_montage_file(desc, duration) end

---删除剧情文件
---@param montage_id Str 剧情id
function EditorAPI.delete_montage_file(montage_id) end

---获取剧情文件key列表
---@return List key文件名映射
function EditorAPI.get_montage_file_list() end

---输入剧情数据
---@param path Str 剧情文件路径
function EditorAPI.input_new_montage_data(path) end

---输出剧情数据
---@param montage_id Str 剧情ID
---@param path Str 剧情文件路径
---@return Dict 剧情数据
function EditorAPI.output_montage_data(montage_id, path) end

---截取当前屏幕并保存为图片文件
---@return Str 截图保存路径
function EditorAPI.take_screenshot() end

---截取当前屏幕并保存为指定尺寸的图片文件
---@param width Int 宽度
---@param height Int 高度
---@return Str 截图保存路径
function EditorAPI.take_screenshot_with_size(width, height) end

---h5内初始化蛋仔模型预览场景
---@param plugin_id Str plugin_id-h5里backend.getPluginId / 自定义唯一键
---@param sub_id Str sub_id-适用于同一个插件里可能用到多个预览场景时
function EditorAPI.init_preview_scene(plugin_id, sub_id) end

---销毁h5蛋仔模型预览场景
---@param controller_id Str controller_id-通过init_preview_scene拿到的h5场景唯一id
function EditorAPI.destroy_preview_scene(controller_id) end

---h5内对指定蛋仔模型进行预览
---@param controller_id Str controller_id-从init_preview_scene返回的场景窗id
---@param model_path Str model_path-待预览的neox模型路径
---@param target_x Fixed target_x-预览的位置x
---@param target_y Fixed target_y-预览的位置y
---@param target_z Fixed target_z-预览的位置z
function EditorAPI.preview_model(controller_id, model_path, target_x, target_y, target_z) end

---h5内对指定特效进行预览
---@param controller_id Str controller_id
---@param sfx_path Str sfx特效路径
---@param target_x Fixed 目标X
---@param target_y Fixed 目标Y
---@param target_z Fixed 目标Z
function EditorAPI.preview_sfx(controller_id, sfx_path, target_x, target_y, target_z) end

---h5内对指定预设组件进行预览
---@param controller_id Str controller_id-从init_preview_scene返回的场景窗id
---@param prefab_id Int prefab_id-预设id
---@param target_x Fixed target_x-预览的位置x
---@param target_y Fixed target_y-预览的位置y
---@param target_z Fixed target_z-预览的位置z
function EditorAPI.preview_prefab(controller_id, prefab_id, target_x, target_y, target_z) end

---h5插件内清空特定场景
---@param controller_id Str controller_id-从init_preview_scene返回的场景窗id
function EditorAPI.clear_preview(controller_id) end

---设置拜访模型的旋转
---@param controller_id Str controller_id-从init_preview_scene返回的场景窗id
---@param yaw Fixed 偏转角
---@param pitch Fixed 俯仰角
---@param roll Fixed 旋转角
function EditorAPI.set_model_rotation(controller_id, yaw, pitch, roll) end

---设置模型位置
---@param controller_id Str controller_id-从init_preview_scene返回的场景窗id
---@param x Fixed x
---@param y Fixed y
---@param z Fixed z
function EditorAPI.set_model_position(controller_id, x, y, z) end

---设置相机距离
---@param controller_id Str controller_id-从init_preview_scene返回的场景窗id
---@param distance Fixed 相机距离
function EditorAPI.set_camera_distance(controller_id, distance) end

---设置相机轨道
---@param controller_id Str controller_id-从init_preview_scene返回的场景窗id
---@param azimuth Fixed 方位角
---@param elevation Fixed 仰角
---@param distance Fixed 相机到目标点距离
---@param target_x Fixed 目标点X
---@param target_y Fixed 目标点Y
---@param target_z Fixed 目标点Z
function EditorAPI.set_camera_orbit(controller_id, azimuth, elevation, distance, target_x, target_y, target_z) end

---启动预览场景的帧推流-帧数据将通过 backendSignal 信号推送，格式为{'method': 'frameReady', 'plugin_name': str, 'sub_id': str, 'data': 'data:image/png;base64,...'}
---@param controller_id Str controller_id-从init_preview_scene返回的场景窗id
---@param width Int 预览窗宽度
---@param height Int 预览窗高度
function EditorAPI.start_preview_stream(controller_id, width, height) end

---停止预览场景的帧流
---@param controller_id Str 控制器ID
function EditorAPI.stop_preview_stream(controller_id) end

---获取EUI树状数据
---@return Dict UI树数据
function EditorAPI.get_eui_tree_data() end

---高亮EUI节点
---@param node_id ENode 节点ID
---@return Dict 节点边界信息
function EditorAPI.highlight_eui_node(node_id) end

---清除EUI高亮
---@return Bool 是否成功
function EditorAPI.clear_eui_highlight() end

---创建预设
---@param prefab_type Str 预设类型
---@param package_id Str 包ID
---@param folder_key Str 文件夹Key
function StateSyncEditorApi.create_asset_cmd(prefab_type, package_id, folder_key) end

---创建子预设
---@param asset_key Str 预设Key
---@param unit_type Str 单位类型
---@param override_data SELuaTable 覆盖数据
function StateSyncEditorApi.create_sub_asset_cmd(asset_key, unit_type, override_data) end

---删除子预设
---@param asset_key Str 预设Key
function StateSyncEditorApi.remove_sub_asset_cmd(asset_key) end

---删除预设
---@param asset_id_list List 预设ID列表
---@param package_id Str 包ID
function StateSyncEditorApi.remove_asset_cmd(asset_id_list, package_id) end

---复制预设
---@param asset_ids List 预设ID列表
---@param package_id Str 包ID
---@param folder_key Str 文件夹Key
function StateSyncEditorApi.duplicate_asset_cmd(asset_ids, package_id, folder_key) end

---应用预设到场景
---@param asset_id Str 预设ID
function StateSyncEditorApi.apply_asset_to_scene_cmd(asset_id) end

---从单位同步预设数据
---@param unit_id Int 单位ID
function StateSyncEditorApi.sync_asset_from_unit_cmd(unit_id) end

---通过预设创建单位
---@param asset_id Str 预设ID
---@param create_pos List 世界坐标
---@param create_angle List 旋转角度
---@param create_scale List 缩放
---@return List 单位ID列表
function StateSyncEditorApi.create_unit_by_asset(asset_id, create_pos, create_angle, create_scale) end

---获取预设属性值
---@param asset_id Str 预设ID
---@param attr_key Str 属性名
---@param default SEAny 默认值
---@return SEAny 属性值
function StateSyncEditorApi.get_asset_value(asset_id, attr_key, default) end

---获取预设单位数据
---@param asset_id Str 预设ID
---@return SELuaTable 单位数据
function StateSyncEditorApi.get_asset_unit_data(asset_id) end

---获取预设序列化数据
---@param asset_id Str 预设ID
---@return SELuaTable 序列化数据
function StateSyncEditorApi.get_asset_serialize_data(asset_id) end

---修改预设属性值
---@param asset_id Str 预设ID
---@param change_data_list List 修改数据列表
---@param package_id Str 包ID
function StateSyncEditorApi.change_asset_value_cmd(asset_id, change_data_list, package_id) end

---重置预设数据
---@param asset_id Str 预设ID
---@param package_id Str 包ID
function StateSyncEditorApi.reset_asset_cmd(asset_id, package_id) end

---获取所有预设ID
---@return List 预设ID列表
function StateSyncEditorApi.get_all_asset_ids() end

---按类型获取预设ID
---@param prefab_type Str 预设类型
---@return List 预设ID列表
function StateSyncEditorApi.get_prefab_eids_by_type(prefab_type) end

---获取预设单位类型
---@param prefab_key Str 预设Key
---@return Str 单位类型
function StateSyncEditorApi.get_asset_unit_type(prefab_key) end

---获取预设默认数据
---@param prefab_type Str 预设类型
---@return SELuaTable 默认数据
function StateSyncEditorApi.get_prefab_default_data(prefab_type) end

---创建预设文件夹
---@param package_id Str 包ID
---@param folder_key Str 文件夹Key
---@param name Str 文件夹名称
---@param parent_folder_key Str 父文件夹Key
function StateSyncEditorApi.create_asset_folder_cmd(package_id, folder_key, name, parent_folder_key) end

---移动预设文件夹
---@param package_id Str 包ID
---@param folder_key Str 文件夹Key
---@param new_parent_folder_key Str 新父文件夹Key
function StateSyncEditorApi.move_asset_folder_cmd(package_id, folder_key, new_parent_folder_key) end

---重命名预设文件夹
---@param package_id Str 包ID
---@param folder_key Str 文件夹Key
---@param new_name Str 新名称
function StateSyncEditorApi.rename_asset_folder_cmd(package_id, folder_key, new_name) end

---移动预设到文件夹
---@param package_id Str 包ID
---@param folder_key Str 文件夹Key
---@param asset_ids List 预设ID列表
function StateSyncEditorApi.move_assets_to_folder_cmd(package_id, folder_key, asset_ids) end

---复制预设文件夹
---@param folder_keys List 文件夹Key列表
---@param package_id Str 包ID
function StateSyncEditorApi.duplicate_asset_folder_cmd(folder_keys, package_id) end

---获取包内文件夹Key列表
---@param package_id Str 包ID
---@return List 文件夹Key列表
function StateSyncEditorApi.get_package_prefab_folder_keys(package_id) end

---获取文件夹数据
---@param package_id Str 包ID
---@param folder_key Str 文件夹Key
---@return SELuaTable 文件夹数据
function StateSyncEditorApi.get_package_prefab_folder_data(package_id, folder_key) end

---获取文件夹内预设Key列表
---@param folder_key Str 文件夹Key
---@return List 预设Key列表
function StateSyncEditorApi.get_asset_keys_in_folder(folder_key) end

---获取预设所在文件夹Key
---@param asset_id Str 预设ID
---@return Str 文件夹Key
function StateSyncEditorApi.get_asset_folder_key(asset_id) end

---获取所有包ID列表
---@return List 包ID列表
function StateSyncEditorApi.get_package_id_list() end

---获取包对象
---@param package_id Str 包ID
---@return SEAny 包对象
function StateSyncEditorApi.get_asset_package(package_id) end

---获取预设所属包ID
---@param asset_id Str 预设ID
---@return Str 包ID
function StateSyncEditorApi.get_asset_package_id(asset_id) end

---按索引获取包ID
---@param index Int 索引
---@return Str 包ID
function StateSyncEditorApi.get_package_id_by_index(index) end

---获取包可编辑参数
---@param package_id Str 包ID
---@return List 参数列表
function StateSyncEditorApi.get_package_editable_params(package_id) end

---获取包内所有预设Key
---@param package_id Str 包ID
---@return List 预设Key列表
function StateSyncEditorApi.get_all_asset_keys(package_id) end

---获取预设Meta列表
---@param prefab_type Str 预设类型
---@return SELuaTable Meta数据
function StateSyncEditorApi.get_unit_metas(prefab_type) end

---获取预设属性Meta列表
---@param prefab_type Str 预设类型
---@return List 属性Meta列表
function StateSyncEditorApi.get_unit_attr_meta_list(prefab_type) end

---判断是否为预设Meta
---@param prefab_type Str 预设类型
---@return Bool 是否为Meta
function StateSyncEditorApi.is_unit_meta(prefab_type) end

---判断Meta继承关系
---@param meta_type Str Meta类型
---@param target_meta_type Str 目标Meta类型
---@return Bool 是否为子类型
function StateSyncEditorApi.is_meta_child(meta_type, target_meta_type) end

---获取Meta名称
---@param prefab_type Str 预设类型
---@return Str Meta名称
function StateSyncEditorApi.get_unit_meta_name(prefab_type) end

---获取预设子类型列表
---@param unit_type Str 单位类型
---@return List 子类型列表
function StateSyncEditorApi.get_asset_unit_children_types(unit_type) end

---获取预设根类型
---@param prefab_type Str 预设类型
---@return Str 根类型
function StateSyncEditorApi.get_unit_root_type(prefab_type) end

---获取所有预设Meta
---@return SELuaTable 所有Meta数据
function StateSyncEditorApi.get_package_all_prefab_metas() end

---获取所有单位类型
---@return List 单位类型列表
function StateSyncEditorApi.get_all_unit_types() end

---判断是否可创建单位
---@param unit_type Str 单位类型
---@return Bool 是否可创建
function StateSyncEditorApi.enable_meta_create_unit(unit_type) end

---创建预设(本地直接执行)
---@param prefab_type Str 预设类型
---@param package_id Str 包ID
---@param folder_key Str 文件夹Key
---@return Str 预设ID
function StateSyncEditorApi.create_asset(prefab_type, package_id, folder_key) end

---创建子预设(本地直接执行)
---@param asset_key Str 预设Key
---@param unit_type Str 单位类型
---@param override_data SELuaTable 覆盖数据
---@return Str 子预设Key
function StateSyncEditorApi.create_sub_asset(asset_key, unit_type, override_data) end

---删除子预设(本地直接执行)
---@param asset_key Str 预设Key
---@param asset_sub_key Str 子预设Key
---@return SELuaTable 被删子预设数据
function StateSyncEditorApi.remove_sub_asset(asset_key, asset_sub_key) end

---删除预设(本地直接执行)
---@param asset_id Str 预设ID
---@param package_id Str 包ID
function StateSyncEditorApi.remove_asset(asset_id, package_id) end

---复制预设(本地直接执行)
---@param asset_ids List 预设ID列表
---@param package_id Str 包ID
---@param folder_key Str 文件夹Key
---@return List 新预设数据列表
function StateSyncEditorApi.duplicate_asset(asset_ids, package_id, folder_key) end

---修改单个预设属性(本地直接执行)
---@param asset_id Str 预设ID
---@param attr_key Str 属性名
---@param attr_value SEAny 属性值
---@param package_id Str 包ID
function StateSyncEditorApi.change_asset_value_single(asset_id, attr_key, attr_value, package_id) end

---批量修改预设属性(本地直接执行)
---@param asset_id Str 预设ID
---@param change_data_list List 修改数据列表
---@param package_id Str 包ID
function StateSyncEditorApi.change_asset_value_multi(asset_id, change_data_list, package_id) end

---重置预设(本地直接执行)
---@param asset_id Str 预设ID
---@param package_id Str 包ID
function StateSyncEditorApi.reset_asset(asset_id, package_id) end

---按数据重置预设(本地直接执行)
---@param asset_id Str 预设ID
---@param asset_data SELuaTable 预设数据
---@param package_id Str 包ID
function StateSyncEditorApi.reset_asset_by_data(asset_id, asset_data, package_id) end

---应用预设到场景(本地直接执行)
---@param asset_key Str 预设Key
---@return SELuaTable 操作结果
function StateSyncEditorApi.apply_asset_to_scene(asset_key) end

---从单位同步预设(本地直接执行)
---@param unit_id Int 单位ID
---@return SELuaTable 旧预设数据和ID
function StateSyncEditorApi.sync_asset_from_unit(unit_id) end

---创建预设文件夹(本地直接执行)
---@param package_id Str 包ID
---@param folder_key Str 文件夹Key
---@param name Str 名称
---@param parent_folder_key Str 父文件夹Key
function StateSyncEditorApi.create_asset_folder(package_id, folder_key, name, parent_folder_key) end

---移动预设文件夹(本地直接执行)
---@param package_id Str 包ID
---@param folder_key Str 文件夹Key
---@param new_parent_folder_key Str 新父文件夹Key
function StateSyncEditorApi.move_asset_folder(package_id, folder_key, new_parent_folder_key) end

---删除预设文件夹(本地直接执行)
---@param package_id Str 包ID
---@param folder_key Str 文件夹Key
function StateSyncEditorApi.remove_asset_folder(package_id, folder_key) end

---重命名预设文件夹(本地直接执行)
---@param package_id Str 包ID
---@param folder_key Str 文件夹Key
---@param new_name Str 新名称
function StateSyncEditorApi.rename_asset_folder(package_id, folder_key, new_name) end

---移动预设到文件夹(本地直接执行)
---@param package_id Str 包ID
---@param folder_key Str 文件夹Key
---@param asset_ids List 预设ID列表
function StateSyncEditorApi.move_assets_to_folder(package_id, folder_key, asset_ids) end

---更新文件夹数据(本地直接执行)
---@param package_id Str 包ID
---@param folder_key Str 文件夹Key
---@param folder_data SELuaTable 文件夹数据
function StateSyncEditorApi.update_asset_folder(package_id, folder_key, folder_data) end

---移动子预设(本地直接执行)
---@param asset_key Str 源预设Key
---@param parent_asset_key Str 目标父预设Key
function StateSyncEditorApi.move_sub_asset(asset_key, parent_asset_key) end

---通过预设数据创建单位(本地直接执行)
---@param asset_data SELuaTable 预设数据
---@param create_pos List 坐标
---@param create_angle List 角度
---@param create_scale List 缩放
---@return List 单位ID列表
function StateSyncEditorApi.create_unit_by_asset_data(asset_data, create_pos, create_angle, create_scale) end

---通过数据创建预设(本地直接执行)
---@param asset_data SELuaTable 预设数据
---@param package_id Str 包ID
---@param folder_key Str 文件夹Key
---@return Str 预设ID
function StateSyncEditorApi.create_asset_by_data(asset_data, package_id, folder_key) end

---为单位创建预设(本地直接执行)
---@param unit_id Int 单位ID
---@param folder_key Str 文件夹Key
---@return SELuaTable 包ID和预设ID
function StateSyncEditorApi.create_asset_for_unit(unit_id, folder_key) end

---从单位获取预设数据(本地直接执行)
---@param unit_id Int 单位ID
---@param new_asset_id Str 新预设ID
---@return SELuaTable 预设数据
function StateSyncEditorApi.get_asset_data_from_unit(unit_id, new_asset_id) end

---设置预设序列化数据(本地直接执行)
---@param asset_id Str 预设ID
---@param asset_data SELuaTable 预设数据
function StateSyncEditorApi.set_asset_serialize_data(asset_id, asset_data) end

---删除预设属性(本地直接执行)
---@param asset_id Str 预设ID
---@param attr_key Str 属性名
function StateSyncEditorApi.remove_asset_attr(asset_id, attr_key) end

---获取预设对象
---@param asset_id Str 预设ID
---@return SEAny 预设对象
function StateSyncEditorApi.get_asset(asset_id) end

---获取预设单位类型数量
---@param asset_id Str 预设ID
---@param unit_type Str 单位类型
---@return Int 数量
function StateSyncEditorApi.get_asset_unit_type_count(asset_id, unit_type) end

---判断是否内置Meta
---@param prefab_type Str 预设类型
---@return Bool 是否内置
function StateSyncEditorApi.is_unit_builtin_meta(prefab_type) end

---获取单位父类型
---@param prefab_type Str 预设类型
---@return Str 父类型
function StateSyncEditorApi.get_unit_parent_type(prefab_type) end

---判断是否为预设数据类型
---@param prefab_type Str 预设类型
---@return Bool 是否为数据类型
function StateSyncEditorApi.is_prefab_data_type(prefab_type) end

---获取预设类型到父类型映射
---@return SELuaTable 类型映射
function StateSyncEditorApi.get_prefab_type_2_parent() end

---获取所有单位Meta
---@return SELuaTable 所有Meta
function StateSyncEditorApi.get_all_unit_metas() end

---添加单位Meta
---@param unit_type Str 单位类型
---@param unit_meta_data SELuaTable Meta数据
function StateSyncEditorApi.add_unit_meta(unit_type, unit_meta_data) end

---删除单位Meta
---@param unit_type Str 单位类型
function StateSyncEditorApi.remove_unit_meta(unit_type) end

---获取单位Meta对象
---@param prefab_type Str 预设类型
---@return SEAny Meta对象
function StateSyncEditorApi.get_unit_meta_object(prefab_type) end

---添加单位属性Meta
---@param prefab_type Str 预设类型
---@param attr_meta SELuaTable 属性Meta
function StateSyncEditorApi.add_unit_attr_meta(prefab_type, attr_meta) end

---删除单位属性Meta
---@param prefab_type Str 预设类型
---@param attr_key Str 属性Key
function StateSyncEditorApi.remove_unit_attr_meta(prefab_type, attr_key) end

---获取单位属性Meta
---@param prefab_type Str 预设类型
---@param attr_key Str 属性Key
---@return SEAny 属性Meta
function StateSyncEditorApi.get_unit_attr_meta(prefab_type, attr_key) end

---获取包预设Meta列表
---@param prefab_type Str 预设类型
---@return SELuaTable Meta列表
function StateSyncEditorApi.get_package_prefab_metas(prefab_type) end

---添加预设包
---@param package_id Str 包ID
---@param package_data SELuaTable 包数据
---@return SEAny 包对象
function StateSyncEditorApi.add_asset_package(package_id, package_data) end

---删除预设包
---@param package_id Str 包ID
---@return Int 包索引
function StateSyncEditorApi.remove_asset_package(package_id) end

---获取预设使用计数
---@param asset_id Str 预设ID
---@return Int 使用计数
function StateSyncEditorApi.get_asset_count(asset_id) end

---判断预设是否可创建单位
---@param asset_id Str 预设ID
---@param check_need_count Int 检查数量
---@return Bool 是否可创建
function StateSyncEditorApi.enable_asset_create_unit(asset_id, check_need_count) end

---增加预设使用计数
---@param asset_id Str 预设ID
function StateSyncEditorApi.add_asset_use_count(asset_id) end

---减少预设使用计数
---@param asset_id Str 预设ID
function StateSyncEditorApi.remove_asset_use_count(asset_id) end

---获取绑定EA脚本预设
---@param asset_id Str 预设ID
---@return SELuaTable 脚本预设数据
function StateSyncEditorApi.get_bind_ea_script_asset(asset_id) end

---获取子预设父级ID
---@param asset_key Str 子预设Key
---@return Str 父级ID
function StateSyncEditorApi.get_asset_sub_unit_parent_id(asset_key) end

---获取子预设父级SubKey
---@param asset_key Str 子预设Key
---@return Str 父级SubKey
function StateSyncEditorApi.get_asset_unit_parent_sub_key(asset_key) end

---获取子预设父级AssetKey
---@param asset_key Str 子预设Key
---@return Str 父级AssetKey
function StateSyncEditorApi.get_asset_unit_parent_asset_key(asset_key) end

---获取包中文件夹预设数量
---@param package_id Str 包ID
---@param folder_key Str 文件夹Key
---@return Int 数量
function StateSyncEditorApi.get_package_prefab_eids_num_in_folder(package_id, folder_key) end

---获取文件夹所属包ID
---@param folder_key Str 文件夹Key
---@return Str 包ID
function StateSyncEditorApi.get_asset_folder_package_id(folder_key) end

---获取包预设文件夹对象
---@param package_id Str 包ID
---@param folder_key Str 文件夹Key
---@return SEAny 文件夹对象
function StateSyncEditorApi.get_package_prefab_folder(package_id, folder_key) end

---获取预设类型常量列表
---@param prefab_type Str 预设类型
---@param extra_filter SEAny 额外过滤
---@return List 常量列表
function StateSyncEditorApi.get_prefab_const_list_by_type(prefab_type, extra_filter) end

---获取预设单位子类型表
---@return SELuaTable 类型表
function StateSyncEditorApi.get_asset_unit_children_type_table() end

---获取单位创建Asset用的序列化数据
---@param asset_id Str 预设ID
---@return SELuaTable 序列化数据
function StateSyncEditorApi.get_create_asset_serialize_data(asset_id) end

---判断文件夹是否为包文件夹
---@param folder_key Str 文件夹Key
---@return Bool 是否为包文件夹
function StateSyncEditorApi.is_package_folder_key(folder_key) end

---获取文件夹父文件夹Key
---@param folder_key Str 文件夹Key
---@return Str 父文件夹Key
function StateSyncEditorApi.get_asset_folder_parent_key(folder_key) end

---解析预设ID
---@param asset_id Str 预设ID
---@return List 主键和子键
function StateSyncEditorApi.parse_asset_id(asset_id) end

---合并预设ID
---@param base_id Str 主键
---@param sub_key Str 子键
---@return Str 合并后ID
function StateSyncEditorApi.combine_asset_id(base_id, sub_key) end

---是否官方预设ID
---@param asset_id Str 预设ID
---@return Bool 是否官方
function StateSyncEditorApi.is_official_asset_id(asset_id) end

---是否官方文件夹Key
---@param folder_key Str 文件夹Key
---@return Bool 是否官方
function StateSyncEditorApi.is_official_folder_key(folder_key) end

---获取预设ID层级列表
---@param asset_id Str 预设ID
---@return List 层级列表
function StateSyncEditorApi.get_asset_id_hierarchy(asset_id) end

---检查类型继承匹配
---@param unit_type Str 单位类型
---@param target_types Str 目标类型
---@return Bool 是否匹配
function StateSyncEditorApi.check_unit_type_in(unit_type, target_types) end

---获取预设图标路径
---@param asset_id Str 预设ID
---@return Str 图标路径
function StateSyncEditorApi.get_prefab_icon_path(asset_id) end

---创建原生图标URL
---@param icon_url Str 图标URL
---@return Str 原生URL
function StateSyncEditorApi.create_native_icon_url(icon_url) end

---解包原生图标URL
---@param icon_url Str 图标URL
---@param need_res_prefix Bool 是否需要res前缀
---@return Str 解包后路径
function StateSyncEditorApi.unpack_native_icon_url(icon_url, need_res_prefix) end

---是否允许复制
---@param asset_id Str 预设ID
---@return Bool 是否允许
function StateSyncEditorApi.get_asset_enable_copy(asset_id) end

---是否允许删除
---@param asset_id Str 预设ID
---@return Bool 是否允许
function StateSyncEditorApi.get_asset_enable_delete(asset_id) end

---是否允许编辑
---@param asset_id Str 预设ID
---@return Bool 是否允许
function StateSyncEditorApi.get_asset_enable_edit(asset_id) end

---获取自定义文件夹Key
---@param package_id Str 包ID
---@return Str 文件夹Key
function StateSyncEditorApi.get_custom_folder_key(package_id) end

---是否允许添加子单位
---@param asset_key Str 预设Key
---@return Bool 是否允许
function StateSyncEditorApi.enable_add_child_unit(asset_key) end

---获取有效子类型列表
---@param asset_key Str 预设Key
---@return List 类型列表
function StateSyncEditorApi.gen_unit_valid_children_type_list(asset_key) end

---按单位类型获取有效子类型列表
---@param unit_type Str 单位类型
---@return List 类型列表
function StateSyncEditorApi.get_valid_children_type_list_by_unit_type(unit_type) end

---获取单位可见性
---@param prefab_type Str 预设类型
---@return Bool 是否可见
function StateSyncEditorApi.is_unit_visible(prefab_type) end

---获取单位父类型
---@param prefab_type Str 预设类型
---@return Str 父类型
function StateSyncEditorApi.get_asset_unit_parent_type(prefab_type) end

---创建变量
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param key Str 变量名
---@param value Str 变量值
---@param vtype Str 类型名
---@param size Int 数组大小
---@param folder_id Int 文件夹ID
---@param index Int 位置索引
---@param remark Str 备注
function StateSyncEditorApi.ts_create_kv(ts_key, ts_type, key, value, vtype, size, folder_id, index, remark) end

---修改变量
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param key Str 变量名
---@param value Str 变量值
---@param vtype Str 类型名
---@param size Int 数组大小
---@param folder_id Int 文件夹ID
---@param index Int 位置索引
---@param remark Str 备注
function StateSyncEditorApi.ts_modify_kv(ts_key, ts_type, key, value, vtype, size, folder_id, index, remark) end

---删除变量
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param key Str 变量名
function StateSyncEditorApi.ts_delete_kv(ts_key, ts_type, key) end

---获取变量值
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param key Str 变量名
---@return Str 变量值
function StateSyncEditorApi.ts_get_kv_value(ts_key, ts_type, key) end

---获取变量类型
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param key Str 变量名
---@return Str 类型名
function StateSyncEditorApi.ts_get_kv_type(ts_key, ts_type, key) end

---获取变量列表
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@return List 变量信息列表
function StateSyncEditorApi.ts_get_kv_list(ts_key, ts_type) end

---创建变量文件夹
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param name Str 文件夹名
---@param parent_id Int 父文件夹ID
function StateSyncEditorApi.ts_create_kv_folder(ts_key, ts_type, name, parent_id) end

---删除变量文件夹
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param folder_id Int 文件夹ID
function StateSyncEditorApi.ts_delete_kv_folder(ts_key, ts_type, folder_id) end

---创建临时变量
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@param key Str 变量名
---@param value Str 变量值
---@param vtype Str 类型名
---@param size Int 数组大小
function StateSyncEditorApi.ts_create_temp_kv(ts_key, ts_type, trigger_id, key, value, vtype, size) end

---修改临时变量
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@param ori_key Str 原变量名
---@param new_key Str 新变量名
---@param value Str 变量值
---@param vtype Str 类型名
---@param size Int 数组大小
function StateSyncEditorApi.ts_modify_temp_kv(ts_key, ts_type, trigger_id, ori_key, new_key, value, vtype, size) end

---删除临时变量
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@param keys List 变量名列表
function StateSyncEditorApi.ts_delete_temp_kv(ts_key, ts_type, trigger_id, keys) end

---获取触发器组列表
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@return List 触发器组列表
function StateSyncEditorApi.ts_get_trigger_group_list(ts_key, ts_type) end

---创建触发器组
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param name Str 组名
---@param parent_id Int 父文件夹ID
---@return Int 新触发器组ID
function StateSyncEditorApi.ts_create_trigger_group(ts_key, ts_type, name, parent_id) end

---删除触发器组
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param group_id Int 触发器组ID
function StateSyncEditorApi.ts_delete_trigger_group(ts_key, ts_type, group_id) end

---修改触发器组
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param group_id Int 触发器组ID
---@param attrs Dict 属性字典
function StateSyncEditorApi.ts_modify_trigger_group(ts_key, ts_type, group_id, attrs) end

---获取触发器列表
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param group_id Int 触发器组ID
---@return List 触发器列表
function StateSyncEditorApi.ts_get_trigger_list(ts_key, ts_type, group_id) end

---创建触发器
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param name Str 触发器名
---@param group_id Int 触发器组ID
---@param index Int 位置索引
function StateSyncEditorApi.ts_create_trigger(ts_key, ts_type, name, group_id, index) end

---删除触发器
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
function StateSyncEditorApi.ts_delete_trigger(ts_key, ts_type, trigger_id) end

---修改触发器
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@param attrs Dict 属性字典
function StateSyncEditorApi.ts_modify_trigger(ts_key, ts_type, trigger_id, attrs) end

---追加触发器事件
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@param cls_id Int CLS_ID
function StateSyncEditorApi.ts_create_trigger_event(ts_key, ts_type, trigger_id, cls_id) end

---追加触发器动作
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@param cls_id Int CLS_ID
function StateSyncEditorApi.ts_create_trigger_action(ts_key, ts_type, trigger_id, cls_id) end

---删除触发器事件
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@param element_ids List 事件元素ID列表
function StateSyncEditorApi.ts_delete_trigger_event(ts_key, ts_type, trigger_id, element_ids) end

---删除触发器动作
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@param element_ids List 动作元素ID列表
function StateSyncEditorApi.ts_delete_trigger_action(ts_key, ts_type, trigger_id, element_ids) end

---获取触发器事件列表
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@return List 事件信息列表
function StateSyncEditorApi.ts_get_trigger_event_list(ts_key, ts_type, trigger_id) end

---获取触发器动作列表
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@return List 动作信息列表
function StateSyncEditorApi.ts_get_trigger_action_list(ts_key, ts_type, trigger_id) end

---启用禁用触发器语句
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@param element_ids List 元素ID列表
---@param enable Bool 是否启用
function StateSyncEditorApi.ts_enable_trigger_element(ts_key, ts_type, trigger_id, element_ids, enable) end

---获取Element槽位信息
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@param element_id Str 元素ID
---@return List 槽位信息列表
function StateSyncEditorApi.ts_get_element_args_info(ts_key, ts_type, trigger_id, element_id) end

---设置Element槽位值
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@param element_id Str 元素ID
---@param arg_index Int 槽位索引
---@param value Str 值
---@return Bool 是否成功
function StateSyncEditorApi.ts_set_element_arg_value(ts_key, ts_type, trigger_id, element_id, arg_index, value) end

---设置Element槽位Element
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@param element_id Str 元素ID
---@param arg_index Int 槽位索引
---@param cls_id Int CLS_ID
---@return Bool 是否成功
function StateSyncEditorApi.ts_set_element_arg_element(ts_key, ts_type, trigger_id, element_id, arg_index, cls_id) end

---获取容器子动作列表
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@param element_id Str 容器元素ID
---@return List 子动作列表
function StateSyncEditorApi.ts_get_container_action_list(ts_key, ts_type, trigger_id, element_id) end

---容器追加动作
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@param element_id Str 容器元素ID
---@param cls_id Int CLS_ID
---@param index Int 插入位置
---@return Bool 是否成功
function StateSyncEditorApi.ts_add_container_action(ts_key, ts_type, trigger_id, element_id, cls_id, index) end

---容器删除动作
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@param element_id Str 容器元素ID
---@param action_element_ids List 子动作ID列表
---@return Bool 是否成功
function StateSyncEditorApi.ts_delete_container_action(ts_key, ts_type, trigger_id, element_id, action_element_ids) end

---获取If分支信息
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@param element_id Str IfNode元素ID
---@return Dict 分支信息
function StateSyncEditorApi.ts_get_if_branch_info(ts_key, ts_type, trigger_id, element_id) end

---添加elif分支
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@param element_id Str IfNode元素ID
---@param branch_index Int 分支位置
---@return Bool 是否成功
function StateSyncEditorApi.ts_add_if_elif_branch(ts_key, ts_type, trigger_id, element_id, branch_index) end

---删除elif分支
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@param element_id Str IfNode元素ID
---@param branch_index Int 分支索引
---@return Bool 是否成功
function StateSyncEditorApi.ts_delete_if_elif_branch(ts_key, ts_type, trigger_id, element_id, branch_index) end

---获取子触发器事件列表
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@param element_id Str SubTrigger元素ID
---@return List 事件列表
function StateSyncEditorApi.ts_get_sub_trigger_event_list(ts_key, ts_type, trigger_id, element_id) end

---添加子触发器事件
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@param element_id Str SubTrigger元素ID
---@param cls_id Int CLS_ID
---@return Bool 是否成功
function StateSyncEditorApi.ts_add_sub_trigger_event(ts_key, ts_type, trigger_id, element_id, cls_id) end

---删除子触发器事件
---@param ts_key Int 触发器系统Key
---@param ts_type Int 触发器系统类型
---@param trigger_id Int 触发器ID
---@param element_id Str SubTrigger元素ID
---@param event_element_ids List 事件ID列表
---@return Bool 是否成功
function StateSyncEditorApi.ts_delete_sub_trigger_event(ts_key, ts_type, trigger_id, element_id, event_element_ids) end

---上传图片资产
---@param file_path Str 文件路径
---@param nick_name Str 显示名称
---@param callback Function 回调函数
function StateSyncEditorApi.custom_file_upload_picture(file_path, nick_name, callback) end

---初始化预览场景
---@param plugin_id Str plugin_id
---@param sub_id Str sub_id
function StateSyncEditorApi.init_preview_scene(plugin_id, sub_id) end

---销毁预览场景
---@param controller_id Str 控制器ID
function StateSyncEditorApi.destroy_preview_scene(controller_id) end

---预览模型
---@param controller_id Str controller_id
---@param model_path Str model_path
---@param target_x Fixed target_x
---@param target_y Fixed target_y
---@param target_z Fixed target_z
function StateSyncEditorApi.preview_model(controller_id, model_path, target_x, target_y, target_z) end

---预览特效
---@param controller_id Str controller_id
---@param sfx_path Str sfx特效路径
---@param target_x Fixed 目标X
---@param target_y Fixed 目标Y
---@param target_z Fixed 目标Z
function StateSyncEditorApi.preview_sfx(controller_id, sfx_path, target_x, target_y, target_z) end

---预览预设
---@param controller_id Str controller_id
---@param prefab_id Int prefab_id
---@param target_x Fixed 目标X
---@param target_y Fixed 目标Y
---@param target_z Fixed 目标Z
function StateSyncEditorApi.preview_prefab(controller_id, prefab_id, target_x, target_y, target_z) end

---清除预览
---@param controller_id Str 控制器ID
function StateSyncEditorApi.clear_preview(controller_id) end

---设置模型旋转
---@param controller_id Str controller_id
---@param yaw Fixed yaw
---@param pitch Fixed pitch
---@param roll Fixed roll
function StateSyncEditorApi.set_model_rotation(controller_id, yaw, pitch, roll) end

---设置模型位置
---@param controller_id Str controller_id
---@param x Fixed x
---@param y Fixed y
---@param z Fixed z
function StateSyncEditorApi.set_model_position(controller_id, x, y, z) end

---设置相机距离
---@param controller_id Str controller_id
---@param distance Fixed distance
function StateSyncEditorApi.set_camera_distance(controller_id, distance) end

---设置相机轨道
---@param controller_id Str controller_id
---@param azimuth Fixed 方位角
---@param elevation Fixed 仰角
---@param distance Fixed 距离
---@param target_x Fixed 目标X
---@param target_y Fixed 目标Y
---@param target_z Fixed 目标Z
function StateSyncEditorApi.set_camera_orbit(controller_id, azimuth, elevation, distance, target_x, target_y, target_z) end

---启动预览帧流
---@param controller_id Str controller_id
---@param width Int 宽度
---@param height Int 高度
function StateSyncEditorApi.start_preview_stream(controller_id, width, height) end

---停止预览帧流
---@param controller_id Str 控制器ID
function StateSyncEditorApi.stop_preview_stream(controller_id) end

---获取所有EUI节点ID
---@return List 节点ID列表
function StateSyncEditorApi.get_all_eui_node_ids() end

---按名称查询EUI节点
---@param name Str 节点名称
---@return List EUI节点ID列表
function StateSyncEditorApi.get_eui_node_ids_by_name(name) end

---获取EUI节点子节点列表
---@param node_id ENode 节点ID
---@return List 子节点ID列表
function StateSyncEditorApi.get_eui_node_children(node_id) end

---获取EUI节点父节点ID
---@param node_id ENode 节点ID
---@return ENode 父节点ID
function StateSyncEditorApi.get_eui_node_parent(node_id) end

---获取EUI节点类型
---@param node_id ENode 节点ID
---@return Str 节点类型字符串
function StateSyncEditorApi.get_eui_node_type(node_id) end

---获取EUI节点属性
---@param node_id ENode 节点ID
---@param attr_name Str 属性名
---@return ETypeMeta 属性值
function StateSyncEditorApi.get_eui_node_attr(node_id, attr_name) end

---创建EUI节点（通用）
---@param node_type Str 节点类型
---@param name Str 节点名称
---@param parent_id ENode 父节点ID
---@return ENode 节点ID
function StateSyncEditorApi.create_eui_node(node_type, name, parent_id) end

---通过预设创建EUI节点
---@param prefab_id Int 预设ID
---@param parent_id ENode 父节点ID
---@return ENode 根节点ID
function StateSyncEditorApi.create_eui_node_from_prefab(prefab_id, parent_id) end

---创建EUI 3D Layer节点
---@param parent_id ENode 父节点ID
---@return ENode 节点ID
function StateSyncEditorApi.create_eui_3d_layer_node(parent_id) end

---设置EUI节点属性（通用）
---@param node_id ENode 节点ID
---@param attr_name Str 属性名
---@param value ETypeMeta 属性值
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_node_attr(node_id, attr_name, value) end

---批量设置EUI节点属性
---@param node_id ENode 节点ID
---@param attr_dict Dict 属性字典
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_node_attrs(node_id, attr_dict) end

---设置EUI节点父节点
---@param node_id ENode 节点ID
---@param new_parent_id ENode 目标父节点ID
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_node_parent(node_id, new_parent_id) end

---设置EUI节点同级顺序
---@param node_id ENode 节点ID
---@param index Int 目标索引
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_node_sibling_index(node_id, index) end

---删除EUI节点
---@param node_id ENode 节点ID
---@return Bool 是否成功
function StateSyncEditorApi.destroy_eui_node(node_id) end

---创建EUI图片节点
---@param preset_id Int 预设ID
---@param parent_id ENode 父节点ID
---@param x Float X坐标
---@param y Float Y坐标
---@param width Float 宽度
---@param height Float 高度
---@param name Str 节点名称
---@return EImage 节点ID
function StateSyncEditorApi.create_eui_image_node(preset_id, parent_id, x, y, width, height, name) end

---创建EUI文本节点
---@param parent_id ENode 父节点ID
---@param x Float X坐标
---@param y Float Y坐标
---@param width Float 宽度
---@param height Float 高度
---@param name Str 节点名称
---@param text Str 文本内容
---@return ELabel 节点ID
function StateSyncEditorApi.create_eui_label_node(parent_id, x, y, width, height, name, text) end

---创建EUI按钮节点
---@param preset_id Int 预设ID
---@param parent_id ENode 父节点ID
---@param x Float X坐标
---@param y Float Y坐标
---@param width Float 宽度
---@param height Float 高度
---@param name Str 节点名称
---@return EButton 节点ID
function StateSyncEditorApi.create_eui_button_node(preset_id, parent_id, x, y, width, height, name) end

---创建EUI进度条节点
---@param preset_id Int 预设ID
---@param parent_id ENode 父节点ID
---@param x Float X坐标
---@param y Float Y坐标
---@param width Float 宽度
---@param height Float 高度
---@param name Str 节点名称
---@return EProgressbar 节点ID
function StateSyncEditorApi.create_eui_progressbar_node(preset_id, parent_id, x, y, width, height, name) end

---创建EUI输入框节点
---@param parent_id ENode 父节点ID
---@param x Float X坐标
---@param y Float Y坐标
---@param width Float 宽度
---@param height Float 高度
---@param name Str 节点名称
---@param text Str 默认文本
---@return EInputField 节点ID
function StateSyncEditorApi.create_eui_input_node(parent_id, x, y, width, height, name, text) end

---创建EUI列表节点
---@param parent_id ENode 父节点ID
---@param x Float X坐标
---@param y Float Y坐标
---@param width Float 宽度
---@param height Float 高度
---@param name Str 节点名称
---@return ENode 节点ID
function StateSyncEditorApi.create_eui_listview_node(parent_id, x, y, width, height, name) end

---创建EUI遮罩节点
---@param parent_id ENode 父节点ID
---@param x Float X坐标
---@param y Float Y坐标
---@param width Float 宽度
---@param height Float 高度
---@param name Str 节点名称
---@param clipping_id Int 蒙版图片ID
---@return ENode 节点ID
function StateSyncEditorApi.create_eui_clipping_node(parent_id, x, y, width, height, name, clipping_id) end

---创建EUI动效节点
---@param preset_id Int 预设ID
---@param parent_id ENode 父节点ID
---@param x Float X坐标
---@param y Float Y坐标
---@param width Float 宽度
---@param height Float 高度
---@param name Str 节点名称
---@return ENode 节点ID
function StateSyncEditorApi.create_eui_animation_node(preset_id, parent_id, x, y, width, height, name) end

---创建EUI画布层节点
---@param name Str 节点名称
---@param parent_id ECanvas 父节点ID
---@return ECanvas 节点ID
function StateSyncEditorApi.create_eui_canvas_layer_node(name, parent_id) end

---设置EUI节点位置
---@param node_id ENode 节点ID
---@param x Float x坐标
---@param y Float y坐标
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_node_pos(node_id, x, y) end

---设置EUI节点尺寸
---@param node_id ENode 节点ID
---@param width Float 宽度
---@param height Float 高度
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_node_size(node_id, width, height) end

---设置EUI节点编辑器可见性
---@param node_id ENode 节点ID
---@param visible Bool 是否可见
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_node_visible(node_id, visible) end

---设置EUI节点透明度
---@param node_id ENode 节点ID
---@param opacity Float 透明度0~1
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_node_opacity(node_id, opacity) end

---设置EUI节点名称
---@param node_id ENode 节点ID
---@param name Str 节点名称
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_node_name(node_id, name) end

---设置EUI图片节点贴图
---@param node_id EImage 节点ID
---@param texture_path Str 图片资源路径
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_image_texture(node_id, texture_path) end

---设置EUI图片节点颜色
---@param node_id EImage 节点ID
---@param r Int R
---@param g Int G
---@param b Int B
---@param a Int A
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_image_color(node_id, r, g, b, a) end

---设置EUI文本节点内容
---@param node_id ELabel 节点ID
---@param text Str 文字内容
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_label_text(node_id, text) end

---设置EUI文本节点字号
---@param node_id ELabel 节点ID
---@param font_size Int 字号
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_label_font_size(node_id, font_size) end

---设置EUI文本节点颜色
---@param node_id ELabel 节点ID
---@param r Int R
---@param g Int G
---@param b Int B
---@param a Int A
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_label_color(node_id, r, g, b, a) end

---设置EUI按钮节点文字
---@param node_id EButton 节点ID
---@param text Str 文字内容
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_button_text(node_id, text) end

---设置EUI按钮节点常态图片
---@param node_id EButton 节点ID
---@param texture_path Str 图片资源路径
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_button_normal_image(node_id, texture_path) end

---设置EUI按钮节点启用状态
---@param node_id EButton 节点ID
---@param enabled Bool 是否启用
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_button_enabled(node_id, enabled) end

---设置EUI进度条当前值
---@param node_id EProgressbar 节点ID
---@param value Int 当前进度值
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_progressbar_value(node_id, value) end

---设置EUI进度条最大值
---@param node_id EProgressbar 节点ID
---@param max_value Int 最大进度值
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_progressbar_max(node_id, max_value) end

---设置EUI进度条最小值
---@param node_id EProgressbar 节点ID
---@param min_value Int 最小进度值
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_progressbar_min(node_id, min_value) end

---设置EUI进度条过渡进度
---@param node_id EProgressbar 节点ID
---@param value Int 目标进度值
---@param duration Float 过渡时间(秒)
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_progressbar_transition(node_id, value, duration) end

---设置EUI按钮节点按下图片
---@param node_id EButton 节点ID
---@param texture_path Str 图片资源路径
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_button_pressed_image(node_id, texture_path) end

---设置EUI按钮节点文字颜色
---@param node_id EButton 节点ID
---@param r Int R
---@param g Int G
---@param b Int B
---@param a Int A
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_button_text_color(node_id, r, g, b, a) end

---设置EUI按钮节点文字字号
---@param node_id EButton 节点ID
---@param font_size Int 字号
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_button_font_size(node_id, font_size) end

---设置EUI文本节点字体
---@param node_id ELabel 节点ID
---@param font_key Str 字体路径
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_label_font(node_id, font_key) end

---设置EUI文本节点背景颜色
---@param node_id ELabel 节点ID
---@param r Int R
---@param g Int G
---@param b Int B
---@param a Int A
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_label_background_color(node_id, r, g, b, a) end

---设置EUI文本节点背景不透明度
---@param node_id ELabel 节点ID
---@param opacity Float 不透明度0~1
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_label_background_opacity(node_id, opacity) end

---设置EUI文本节点描边开关
---@param node_id ELabel 节点ID
---@param enabled Bool 是否开启
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_label_outline_enabled(node_id, enabled) end

---设置EUI文本节点描边颜色
---@param node_id ELabel 节点ID
---@param r Int R
---@param g Int G
---@param b Int B
---@param a Int A
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_label_outline_color(node_id, r, g, b, a) end

---设置EUI文本节点描边宽度
---@param node_id ELabel 节点ID
---@param width Float 描边宽度
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_label_outline_width(node_id, width) end

---设置EUI文本节点描边不透明度
---@param node_id ELabel 节点ID
---@param opacity Float 不透明度0~1
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_label_outline_opacity(node_id, opacity) end

---设置EUI文本节点阴影开关
---@param node_id ELabel 节点ID
---@param enabled Bool 是否开启
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_label_shadow_enabled(node_id, enabled) end

---设置EUI文本节点阴影颜色
---@param node_id ELabel 节点ID
---@param r Int R
---@param g Int G
---@param b Int B
---@param a Int A
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_label_shadow_color(node_id, r, g, b, a) end

---设置EUI文本节点阴影X偏移
---@param node_id ELabel 节点ID
---@param x_offset Float X偏移
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_label_shadow_x_offset(node_id, x_offset) end

---设置EUI文本节点阴影Y偏移
---@param node_id ELabel 节点ID
---@param y_offset Float Y偏移
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_label_shadow_y_offset(node_id, y_offset) end

---设置EUI节点交互开关
---@param node_id ENode 节点ID
---@param enabled Bool 是否可交互
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_node_touch_enabled(node_id, enabled) end

---设置EUI节点可见性
---@param node_id ENode 节点ID
---@param visible Bool 是否可见
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_node_canvas_visible(node_id, visible) end

---修改EUI 3D Layer预设属性
---@param node_id ENode 3D Layer节点ID
---@param key Str 属性名
---@param value ETypeMeta 属性值
---@return Bool 是否成功
function StateSyncEditorApi.modify_eui_3d_layer_prefab(node_id, key, value) end

---修改EUI 3D Layer子节点数据
---@param layer_node_id ENode 3D Layer节点ID
---@param child_node_id ENode 子节点ID
---@return Bool 是否成功
function StateSyncEditorApi.sync_eui_3d_layer_child(layer_node_id, child_node_id) end

---获取EUI 3D Layer预设数据
---@param node_id ENode 3D Layer节点ID
---@return Dict 预设数据字典
function StateSyncEditorApi.get_eui_3d_layer_prefab_data(node_id) end

---设置EUI输入框内容
---@param node_id EInputField 节点ID
---@param text Str 文字内容
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_input_field_text(node_id, text) end

---设置EUI输入框占位文字
---@param node_id EInputField 节点ID
---@param placeholder Str 占位文字
---@return Bool 是否成功
function StateSyncEditorApi.set_eui_input_field_placeholder(node_id, placeholder) end

---打开UI编辑器
---@return Bool 是否成功
function StateSyncEditorApi.open_eui_editor() end

---当前是否处于UI编辑模式
---@return Bool 是否处于UI编辑模式
function StateSyncEditorApi.is_in_eui_edit_mode() end

---切换到场景界面预设编辑模式
---@param layer_id ENode 3D Layer节点ID
---@return Bool 是否成功
function StateSyncEditorApi.switch_to_3d_layer_edit_mode(layer_id) end

---切换回普通画布编辑模式
---@return Bool 是否成功
function StateSyncEditorApi.switch_to_normal_canvas_edit_mode() end

---当前是否处于场景界面编辑模式
---@return Bool 是否处于3D编辑模式
function StateSyncEditorApi.is_in_3d_layer_edit_mode() end

---获取全部场景单位数据
---@return Dict 单位数据字典
function StateSyncEditorApi.get_all_scene_unit_data() end

---获取场景单位数据
---@param uid Int 单位ID
---@return SELuaTable 单位数据
function StateSyncEditorApi.get_scene_unit_data(uid) end

---获取单位属性
---@param unit_id UnitID 单位ID
---@param attr_key Str 属性名
---@return SEAny 属性值
function StateSyncEditorApi.get_unit_attr(unit_id, attr_key) end

---设置单位属性
---@param unit_id UnitID 单位ID
---@param attr_key Str 属性名
---@param attr_value SEAny 属性值
function StateSyncEditorApi.set_unit_attr(unit_id, attr_key, attr_value) end

---获取单位自定义属性
---@param unit_id UnitID 单位ID
---@param attr_key Str 属性名
---@return SEAny 属性值
function StateSyncEditorApi.get_unit_kv(unit_id, attr_key) end

---设置单位自定义属性
---@param unit_id UnitID 单位ID
---@param attr_key Str 属性名
---@param attr_type ValueType 属性类型
---@param attr_value SEAny 属性值
function StateSyncEditorApi.set_unit_kv(unit_id, attr_key, attr_type, attr_value) end

---获取相机属性
---@return Dict 相机属性
function StateSyncEditorApi.get_camera_properties() end

---设置相机属性
---@param kv_data Dict 相机属性
function StateSyncEditorApi.set_camera_properties(kv_data) end

---获取自定义地图数据
---@param key Str 自定义数据名
---@return SELuaTable 自定义数据
function StateSyncEditorApi.get_custom_map_data(key) end

---设置自定义地图数据
---@param key Str 自定义数据名
---@param value SELuaTable 自定义数据
function StateSyncEditorApi.set_custom_map_data(key, value) end

---移除自定义地图数据
---@param key Str 自定义数据名
function StateSyncEditorApi.remove_custom_map_data(key) end

---设置天空盒
---@param skybox_id SEAny 天空盒ID
function StateSyncEditorApi.set_skybox(skybox_id) end

---获取当前天空盒
---@return SEAny 天空盒ID
function StateSyncEditorApi.get_cur_skybox() end

---设置天光属性
---@param kv_data Dict 属性字典
function StateSyncEditorApi.set_skylight_properties(kv_data) end

---获取天光属性
---@return Dict 属性字典
function StateSyncEditorApi.get_skylight_properties() end

---设置雾效属性
---@param kv_data Dict 属性字典
function StateSyncEditorApi.set_fog_properties(kv_data) end

---获取雾效属性
---@return Dict 属性字典
function StateSyncEditorApi.get_fog_properties() end

---开始试玩
function StateSyncEditorApi.run_game() end

---停止试玩
function StateSyncEditorApi.stop_game() end

---获取日志
---@return Str 日志内容
function StateSyncEditorApi.get_editor_log() end

---输出日志
---@param content Str 日志内容
function StateSyncEditorApi.log(content) end

---执行游戏指令
---@param content Str 代码
function StateSyncEditorApi.game_execute(content) end

---截取当前屏幕并保存为图片文件
---@return Str 截图保存路径
function StateSyncEditorApi.take_screenshot() end

---截取当前屏幕并保存为指定尺寸的图片文件
---@param width Int 宽度
---@param height Int 高度
---@return Str 截图保存路径
function StateSyncEditorApi.take_screenshot_with_size(width, height) end

