# 程序员试玩结论

口径：只写根因与改法，不改 `index.lua`、不改素材。代码以 `maifangji/project-files/index.lua` 为准（与 `maifangji/index.lua` 同源）。截图以 PNG 实见为准；`maifangji/playtest/vision-findings.json` 有噪声（SSL 失败、把「按钮可见」标成 P0、把故意画的锯齿分界当成裂纹），不采信。Classic 91–100 只走方向键 / OK / 返回。

---

## 根因对照（函数/行号）

全部行号指向 `maifangji/project-files/index.lua`。

| 现象 | 函数 / 数据 | 行号 | 机制 |
| --- | --- | --- | --- |
| 帮助页先画主界面再盖黑罩，脚按钮无 XIC | `mask_except` / `draw_help` | 3603–3669 | `draw_main(sample)` → `mask_except(highlight)` → `draw_control(..., label)` **不传** `asset_base` |
| 无素材时黑框黑字 | `draw_control` 回退 | 3075–3082 | `g:rect(..., { color = BLACK })` 只描边，标签强制 `BLACK`；黑底上等于消失 |
| 有焦点才反白 | `draw_control` 焦点枝 | 3052–3060 | 填黑 + 白字。帮助第 1–8 步焦点在「下一步」，「离开」走回退枝 |
| 帮助脚按钮贴底 | `Layout.ACTIVITIES.help.leave/next` | 993–994 | `{ x=11/336, y=740, w=133, h=60 }`，落在 800 屏最底一行，整段被 mask 涂黑 |
| 底栏三行重叠 7px | `main_actions` 注释 + 坐标 | 1105–1117 | 行起点 607 / 660 / 713，高 60，间距 53 → 每行重叠 7px |
| 绘制倒序、命中正序 | `draw_main_actions` / `touch_input` | 3242–3250 / 2501–2518 | 绘制 `#actions → 11`（后画的在上）；点击 `ipairs` 第一命中 |
| `main_bg` 从 y=60 铺货区 | `draw_main` | 3255–3256 | `image_drawn(g, "main_bg", 0, 60)`，货行 147..497 压在摊位线稿上 |
| 列表槽 150×70，弹层货图 100×40 | `Layout.GOODS_SLOTS` / `modal_visuals.*.goods` | 1052–1060 / 1296–1308 | 列表键名 `goods_lm_`/`goods_lw_`（素材不存在）；弹层 `goods_m_`/`goods_w_`（存在） |
| 售楼/历程底栏离开 + 顶栏返回 | `Layout.actions` houses/records | 1203–1220 | 底栏沿用 Android `leave`（y=745）；因 1bpp 黑尾不可见而加顶栏 `返回`，两键同 `return_main` |
| 选中房名黑底黑字 | `draw_houses` | 2916–2925 | `houses_select1` 缺失则填黑；`house.name` 仍用 `BLACK` |
| 房源简介叠字 | `draw_houses` / `draw_wrapped_text` | 2940–2948 | `lineHeight = 18`，设备字 24px，行盒互相覆盖 |
| Classic 售楼上下键不走按钮 | `key_input` | 2435–2438 | houses 屏 `up`/`down` 直接 `move_house_selection` 并 `return`，焦点锁在「购买」 |
| Classic 左右键主界面无效 | `key_input` | 2448–2465 | 仅买卖/中介弹层改数量；否则 `return false` |

---

## P0 / P1 / P2

### P0

#### ENG-P0-01 帮助脚按钮无 XIC，未聚焦的「离开」黑底黑字消失

- **现象：** 帮助 1–8 步全屏黑罩上只见右下白字「下一步」，左下「离开」肉眼不存在。第 9 步焦点落到「离开」才出现白字，同时「下一步」控件被拿掉。
- **证据路径：**
  - `maifangji/playtest/unique/007-pm-help-1.png`（第 1 步：只有「下一步」）
  - `maifangji/playtest/unique/008-pm-help-2.png`（第 2 步：同上）
  - `maifangji/playtest/unique/015-pm-help-9.png`（第 9 步：焦点在「离开」才可见；无「下一步」）
- **文件/函数：** `draw_help` 3610–3669；`mask_except` 3603–3608；`Layout.ACTIVITIES.help` 992–994；`Layout.actions` help 分支 1221–1231；`draw_control` 3040–3082。
- **改法：**
  1. `draw_help` 给脚按钮传 `asset_base`（新建 `help_next`/`help_leave`，或复用已有描边按钮），**先铺白底再画控件**，不要让回退枝直接画在 mask 上。
  2. 无素材回退改为：白底 + 黑框 + 黑字；焦点：黑底白字。禁止「只描黑边 + 黑字」落在黑底。
  3. 第 9 步保留双按钮（「下一步」改「完成」或禁用），「离开」位置不变。
- **验收：** 帮助 1–9 每一帧同时能读出「离开」和「下一步/完成」。Classic 把焦点从「下一步」挪到「离开」时，失焦键仍有白框；OK「离开」与返回键都能回主界面。

#### ENG-P0-02 货列表键名与槽尺寸对不上现有 XIC，字压在 `main_bg` 摊位上

- **现象：** 行情五行是 150×70 命中槽，但列表走 `goods_lm_*` / `goods_lw_*`（包内无此键，`draw_control` 回退成黑框黑字）。摊位线稿从 y=60 铺到状态栏，第 4–5 行（新风滤芯 / 老头乐车 / 阅星瞳X4P）被柜台切开；`draw_column_divider` 的晃动折线穿价格列。弹层货图则是另一套 100×40 的 `goods_m_*` / `goods_w_*`（素材存在）。
- **证据路径：**
  - `maifangji/playtest/unique/008-pm-help-2.png`（「阅星瞳X4P」被货箱切断）
  - `maifangji/playtest/unique/016-pm-playing.png`（「新风滤芯」压玻璃柜，价格列被折线切，「老头乐车」贴状态栏）
  - `maifangji/playtest/unique/017-pm-buy-overlay.png`（弹层货格约 100×40，与列表槽不成比例）
  - `maifangji/playtest/unique/047-engineer-houses-leave.png`（离开售楼后的对局帧，同样切字）
  - `maifangji/project-files/manifest.json` 只预载 `goods_m_*`/`goods_w_*`，没有 `goods_lm_`/`goods_lw_`
- **文件/函数：** `Layout.GOODS_SLOTS` 1052–1060（`w=150,h=70,step=70,art_w=135,art_h=54`）；`draw_main` 3255；`draw_main_columns` 3122–3153；`draw_trade_overlay` 3424–3428；`modal_visuals.buy_goods.goods` 1298（`w=100,h=40`）；`draw_column_divider` 3179–3202。
- **改法：**
  1. 列表改为使用已有 `goods_m_`/`goods_w_`，或按 150×70 补 `goods_lm_`/`goods_lw_` 并写入 manifest；禁止再对空键走黑框回退。
  2. `main_bg` 只保留表头/雨棚，货行 147..508 铺白再画字；或把摊位线稿裁到状态栏以下。
  3. 分界线若保留，限制在 `Layout.COLUMN_DIVIDER.x` 的空隙内，不得穿过 `market_price_box`。
  4. 弹层货格与列表槽用同一套尺寸，或弹层只显示货名、不拉小图。
- **验收：** 任意 5 条在售货名+价格完整可读，不与线稿轮廓、折线、状态栏相交。点开买入弹层，货名与列表一致、不出现空白 100×40 小框对 150×70 大槽。抽测含「阅星瞳X4P」「新风滤芯」「老头乐车」的帧。

#### ENG-P0-03 售楼部选中房名黑底黑字；简介行距 18px 叠在 24px 字上

- **现象：** 第一套房名区域是纯黑块，名称不可读，只剩「售价」。两套简介笔画互压。底栏「购买」为焦点（黑底白字），「离开」因函数里先铺白底所以仍可见；顶栏另有「返回」。
- **证据路径：**
  - `maifangji/playtest/unique/021-pm-houses.png`
  - `maifangji/playtest/unique/046-engineer-houses.png`（同构，房价已涨）
- **文件/函数：** `draw_houses` 2878（`page.head` 填黑 h=267）、2916–2925（`houses_select1` 缺失填黑 + `center(..., BLACK)`）、2940–2948（`lineHeight=18`）；`Layout.ACTIVITIES.houses.rowFields` 1018–1025；`HOUSE_DESCRIPTIONS` 2707–2718。
- **改法：**
  1. 选中态：有 `houses_select1` 就画图；无图则**白底黑框**或黑底**白字**画房名，禁止黑+黑。
  2. `draw_wrapped_text` 行高改为 ≥24（与「设备字体只有 24px」注释一致），简介区 `h=104` 按 24 算最多 4 行。
  3. `page.head` 不要盖到第一行卡片（现在 head.h=267，行从 y=96 起）。
- **验收：** 选中/未选中两套房名、售价、简介都不叠字、不黑底消失。Pro 点「离开」或「返回」都回主界面（047 已证明离开有效，回归时不要破坏）。

---

### P1

#### ENG-P1-01 底栏三行命中矩形重叠 7px；XIC 图标画出命中盒，帮助高亮被切顶

- **现象：** 市场行 y=607、服务行 y=660、脚行 y=713，各高 60，垂直间距 53，重叠带 7px。绘制从 `records` 倒画到 `market1`，点击按数组正序取第一命中——注释写明这是为了让「后画的 = 先命中的」。7px 条带本身一致，但 `main_bank` 等 XIC 图标伸出 60px 盒外：帮助第 7 步按命中盒挖洞，医院图标上半被 mask 切掉。
- **证据路径：**
  - `maifangji/playtest/unique/016-pm-playing.png`、`048-engineer-classic-focus-walk.png`（三行视觉叠压：银行图标压在「二手市场」上）
  - `maifangji/playtest/unique/013-pm-help-7.png`（「医院」高亮顶被切）
  - `maifangji/playtest/unique/015-pm-help-9.png`（「中介」高亮同样贴着切边）
- **文件/函数：** `main_actions` 1105–1117；`draw_main_actions` 3242–3250；`touch_input`/`Layout.hit` 2501–2518、1570–1573；`Layout.help_highlights` 1144–1168（高亮矩形 = `main_action_rect`，等于命中盒）。
- **改法：**
  1. 三行改成无重叠：例如行高 56、间距 64，或服务行改为 4×等宽且与市场行、脚行留 8px 缝。
  2. XIC 画在命中盒内（裁切或重出 100×60 / 133×60 稿），`mask_except` 才能跟手。
  3. 去掉「反向存储」注释所保护的重叠；绘制顺序与 `ipairs` 命中改为同一套从上到下的矩形。
- **验收：** 任意底栏按钮的可见图标完全落在自己的 `Layout.hit` 矩形内。点 7px 旧重叠带不再误入上一行。帮助 5–9 步挖出的按钮完整，不被黑罩切顶。

#### ENG-P1-02 弹层打开时主界面底栏仍画出来，但点不到

- **现象：** 买入/银行等弹层盖住现金/存款，底栏市场键从弹层下露出。`active_actions` 在有 overlay 时只返回 `overlay_actions`，底栏看起来活、其实死。快捷数量行（`frame.y + 127`）又跟市场键画在同一条带上。
- **证据路径：** `maifangji/playtest/unique/017-pm-buy-overlay.png`（5/2/1 压在二手/农贸/批发上；现金条被切成「现」「存」）
- **文件/函数：** `active_actions` 2408–2412；`overlay_frames.buy_goods` 1264–1267（y=455, h=127+36）；`quantity_actions` 1461；`View.draw` 先 `draw_main` 再 `draw_overlay` 3672–3679。
- **改法：** overlay 期间不调用 `draw_main_actions`，或弹层铺满底栏；把现金/存款抄进弹层页眉。快捷数量放进弹层内部，不要借主界面按钮当背景。
- **验收：** 打开买/卖/银行/医院/中介/结束确认时，底栏不可见或明确灰掉；点原底栏坐标要么落到弹层键，要么无操作。现金、存款数字仍可读。

#### ENG-P1-03 Classic 售楼部方向键被房源选择吞掉，焦点无法离开「购买」

- **现象：** 进售楼 `saved.focus = 1`（购买）。`up`/`down` 只改 `selected_house` 然后 return，永远不走 `next_enabled`。Classic 不能把焦点挪到「离开」或顶栏「返回」，只能按返回键退出。Pro 点「离开」有效（047 回到对局主界面）。
- **证据路径：** `maifangji/playtest/unique/021-pm-houses.png`、`046-engineer-houses.png`（购买始终是黑底焦点）；`maifangji/playtest/unique/047-engineer-houses-leave.png`（Pro 离开后的主界面）。
- **文件/函数：** `open_houses` 2135–2141；`key_input` 2435–2438；`Layout.actions` houses 1203–1212。
- **改法：** 售楼 `up`/`down` 继续翻房源；`left`/`right` 在「购买 / 离开 / 返回」间移动焦点。或把三个按钮做成独立焦点环，房源翻页改用左右。返回键保持退出。
- **验收：** Classic 不靠返回键也能聚焦并 OK「离开」回到主界面；上下仍能把选中房从第 1 套翻到第 2 套。

---

### P2

#### ENG-P2-01 历程表顶「返回」+ 底「离开」双出口；黑尾素材一旦补上，底栏会再消失

- **现象：** 历程表顶栏「返回」白框白字可见；底栏「离开」因 `records_leave` / `records_tail` 都不存在，落在白底上，焦点态是黑底白字，当前能看见。代码注释写明底栏是 Android 原键、在 1bpp 黑尾上会消失，所以才加顶栏。
- **证据路径：** `maifangji/playtest/unique/022-pm-records.png`；Classic 91 `playtest/runs/091/classic-help-or-action.png`（OK「历程表」进入此页，焦点在「离开」）。
- **文件/函数：** `Layout.actions` records 1213–1220；`draw_records` 2975–3013。
- **改法：** 选定一个主出口：要么保证底栏 `leave` 永远有白底/白框（不依赖 `records_tail`），顶栏「返回」可删；要么只留顶栏，底栏矩形从 `actions` 拿掉，避免双 `return_main`。售楼部同样处理。
- **验收：** 历程表、售楼部各只剩一套语义清晰的退出；补 `*_tail` XIC 后退出键对比度不回退。Classic OK 默认焦点即可退出。

#### ENG-P2-02 帮助文案「30/100」与高亮里的「70/100」不是同一套记法

- **现象：** 帮助第 3 步文案写「30/100 表示最多存放 100 件，目前还剩 30 个空位」，高亮标题是「出租屋（70/100）」——代码里 `used=70, capacity=100`，UI 是占用/容量，文案把剩余写成了分数左项。
- **证据路径：** `maifangji/playtest/unique/009-pm-help-3.png`；`View.HELP_EXPLANATIONS[3]` 2698；`draw_help` sample `used=70` 3616–3623。
- **改法：** 文案改成与标题同一记法（「70/100 表示已放 70 件，一共 100 格」），或 sample 改成能对上原文的数。不要改玩法。
- **验收：** 帮助第 3 步标题数字与正文同一含义，读一遍对得上。

---

## 命中与绘制不一致

1. **底栏三行：** 绘制 `draw_main_actions` 从 index `#actions` 画到 11（脚行先画、市场后画在上）；点击 `touch_input` 按 `ipairs` 正序（市场行先命中）。注释 1105–1107 故意用反向存储对齐这 7px 重叠带。重叠带内命中=可见顶层，**一致**；盒外伸出的图标 **不一致**（见 ENG-P1-01）。
2. **帮助脚按钮：** 命中矩形在 y=740，绘制也在 y=740，几何一致；但 `draw_help` 不传 XIC，回退黑字，未聚焦键 **命中在、看不见**（ENG-P0-01）。
3. **货槽：** 命中 150×70（`buy_1..5` / `sell_1..5`）；列表 XIC 键 `goods_lm_`/`goods_lw_` 不存在，画出的是整槽描边+字；弹层命中/绘制却是 100×40 的 `goods_m_`/`goods_w_`。同一货物两套矩形（ENG-P0-02）。
4. **`main_bg`：** 从 (0,60) 整图贴上，不是命中目标，但覆盖全部货槽。玩家点的是槽，看到的是摊位线稿+字。
5. **售楼/历程：** 顶栏「返回」(12,8,80,36) 与底栏「离开」(347/207,745,67,39) 都是 `return_main`，两套命中、两套绘制。Pro 都点得到。Classic 售楼只能用返回键，因为方向键不移动这两个焦点（ENG-P1-03）。
6. **弹层 vs 底栏：** 主界面底栏照常绘制，overlay 期间不进入 `Layout.actions` 命中链。看见的键点不着（ENG-P1-02）。例外：`quit_game`/`new_game` 在 `touch_input` 2527–2530 点框外会先关层再把点击转给主界面——真机 Click/OK 抢焦点的补丁，和其他弹层行为不一致。

---

## Classic 键位

依据：`key_input` 2429–2483；空仓 `Layout.actions` 把买/卖/市场/银行/医院/售楼/中介全部 `disabled`；`clamp_focus` / `next_enabled` 只在未禁用项上绕环。试玩 91–100（`x4_classic` / `classic-keys`）十局指纹相同，无 error。048 是空仓焦点走到「历程表」的去重帧。

| 键 | 主界面（空仓） | 主界面（对局） | 帮助 | 历程表 | 售楼部 | 弹层 |
| --- | --- | --- | --- | --- | --- | --- |
| 上/下 | 在「帮助 → 开始游戏 → 历程表」三点环绕。048 停在「历程表」 | 沿最多 20 个一维列表走（五行买、有货才卖、三市场、四服务、三脚键），无二维网格 | 在「下一步 / 离开」间切换；离开未聚焦时看不见 | 在「离开 / 返回」间切换 | **不走按钮**，只改 `selected_house` | 在 overlay 按钮间切换 |
| 左/右 | `return false`，无操作 | 同左 | 无操作 | 无操作 | 无操作 | 仅买/卖/中介改数量 |
| OK | 激活焦点。空仓默认 clamp 到「帮助」；走到「历程表」再 OK 进历程表（91 `classic-help-or-action`） | 买/卖/进市场/开服务 | 下一步翻页；看不见的「离开」被聚焦后 OK 也能退 | 默认焦点「离开」即退出 | 默认「购买」，无法 OK 到「离开」 | 激活当前 overlay 键 |
| 返回 | 无上层则 `back` 失败留在主界面 | 关 overlay / 退全屏页 | 回主界面 | 回主界面 | **唯一可靠的退出** | 关层 |

结论：

1. 空仓可走的只有脚行三个键。脚本式「一直 Down」会停在「历程表」而不是「开始游戏」，91–100 因此大量进历程表/帮助，对局主界面不是这十局的稳定终点。
2. 没有左右网格：要从「蛋白粉罐」走到「历程表」得连按 Down 穿过整表。这和底栏三列视觉布局不符。
3. 帮助页 Classic 能用 Down 摸到「离开」再 OK 退出，但玩家看不到那个键（ENG-P0-01）。返回键是看得见的退路。
4. 售楼部 Classic 方向键与按钮焦点互斥（ENG-P1-03）。不修的话必须在帮助里写明「按返回离开售楼部」。
5. 改法（键位层）：主界面 `left`/`right` 在同行三列间移动，`up`/`down` 在五行货 + 三行底栏间移动；售楼 `left`/`right` 走购买/离开/返回。不要让 `disabled` 项占用焦点（现有 `next_enabled` 已跳过，保持）。

---

改这几处时不要动玩法数值、不要手压 ZIP。先让 `draw_control` 在无图时有对比度，再补列表货图键名，最后拆底栏重叠。
