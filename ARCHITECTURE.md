# 社区咖啡烘焙工坊订阅服务 - 架构笔记

> 这篇是写给新同事看的快速上手笔记，看完你应该能搞懂这个后端到底在干嘛、数据是怎么流转的、哪些业务规则是坑。
> 代码用的是 Sinatra + ActiveRecord + SQLite，测试用 RSpec + FactoryBot。

---

## 一、项目是干嘛的

这是一个社区咖啡烘焙工坊的**订阅服务后端**。说白了就是帮工坊做两件事：

1. **给客户用**：能浏览豆子、单次下单买咖啡豆，或者开一个定期配送的订阅（每周/双周/每月自动发），随时可以暂停、跳过下次配送、查历史收货记录。
2. **给老板用**：能上新豆子、调整库存、按烘焙批次生成配送单、管理优惠码。

用户角色就两种：
- **customer（客户）**：买咖啡的
- **admin（管理员/老板）**：管豆子、管库存、管配送、管优惠码

---

## 二、实体关系（模型之间怎么勾连）

不用画 UML，顺着业务走一遍你就明白了。所有外键都是 `*_id` 的形式。

### User（用户）
- 一个 user 有**多个** Address（收货地址）
- 一个 user 有**多个** Order（订单）
- 一个 user 有**多个** Subscription（订阅）
- 一个 user 有**多个** PromoCodeRedemption（优惠码使用记录，每个码每个用户只能用一次）

### Address（地址）
- 属于**一个** User
- 一个地址可以被**多个** Order 或 Subscription 使用
- 有 `is_default` 标记默认地址，有 `locked` 字段（后面业务规则会讲冻结是什么意思）

### CoffeeBean（咖啡豆）
- 核心商品，有产地、烘焙度、风味描述、每 100g 价格、当前库存克数、是否在售
- 一个豆子有**多个** RoastBatch（烘焙批次）
- 一个豆子会被**多个** OrderItem / SubscriptionItem 引用

### Order & OrderItem（订单 & 订单项）
- Order 属于**一个** User 和**一个** Address
- 一个 Order 有**多个** OrderItem（一个订单可以买好几种豆子）
- OrderItem 里存了 `quantity_grams`（买了多少克）、`unit_price`（当时的单价）、`subtotal`（这一项多少钱）
- Order 可以关联**一个** PromotionCode（用了哪个优惠码，可选）
- Order 可以生成**一个** Shipment（配送单）

### Subscription & SubscriptionItem（订阅 & 订阅项）
- 跟订单几乎是镜像结构：
  - Subscription 属于**一个** User 和**一个** Address
  - 一个 Subscription 有**多个** SubscriptionItem
  - 可以关联**一个** PromotionCode
- 多出来的字段：`frequency`（weekly/biweekly/monthly）、`start_date`、`next_delivery_date`、`skip_next_count`

### RoastBatch（烘焙批次）
- 属于**一个** CoffeeBean
- 存了 `roast_quantity_grams`（这次烘了多少克）、`roasted_at`（烘焙时间）
- 创建批次后会**自动把烘焙量加到豆子的库存里**（after_create 回调）
- 一个批次可以生成**多个** Shipment（用这一批豆子给多个客户发货）

### Shipment（配送单）
- 核心是"某一批豆子，在某一天，发给某个地址多少克"
- 属于**一个** RoastBatch 和**一个** Address
- 关联**一个** Subscription **或**一个** Order（二选一，不能同时关联两个）
- 存了 `total_weight_grams`（这次发了多少克）、`scheduled_date`（计划发货日）

### PromotionCode（优惠码）
- 可以被**多个** Order / Subscription 使用，但**每个用户只能用一次**（不管是订单还是订阅）
- 有 `discount_type`（fixed 立减 / percentage 折扣）、`discount_value`、`max_uses`、`used_count`、`expires_at`、`active`

### PromoCodeRedemption（优惠码使用记录）
- 属于**一个** User 和**一个** PromotionCode
- 联合唯一索引 `(promotion_code_id, user_id)` 从数据库层面保证"一人一码一次"
- 关联**一个** Order **或**一个** Subscription（记录这次是用在什么地方）
- 存了 `redeemed_at`（使用时间），审计用

---

## 三、业务规则（重点，这些是坑）

### 3.1 地址冻结（locked 字段）
- **什么时候冻结**：用户创建订阅成功那一刻，订阅关联的地址自动被 `lock_address!` 锁上。
- **冻结是什么意思**：地址不能改、不能删，但可以继续被这个订阅用来发货。想改地址得先取消订阅，或者联系老板后台手动改。
- **为什么要冻结**：订阅生效后配送地址不能中途变，否则配送单会乱。

### 3.2 下次发货日怎么算
- 三档频率对应的天数：`weekly=7`、`biweekly=14`、`monthly=30`（硬编码在 `Subscription::FREQUENCIES` 里）
- 每次发货后（配送单生成成功），调用 `calculate_next_delivery_date!`：
  - 公式：`next_delivery_date = 上次 next_delivery_date + (skip_next_count + 1) * frequency_days`
  - 然后 `skip_next_count` 重置为 0
- **跳过一次配送（skip_next!）**：只是 `skip_next_count += 1`，不会改 `next_delivery_date`，真正挪日期是在生成配送单的时候一起算。
- **暂停（pause!）**：只是把 `status` 改成 `paused`，`next_delivery_date` 不动，恢复（resume!）后还是原来的日期。
- **老板手动取消配送单（cancel!）**：会把订阅的 `next_delivery_date` 回退到这个配送单的 scheduled_date，相当于这次不算发货，下次还是这天发。

### 3.3 库存扣减逻辑
- **下单时扣库存**：创建 Order 的事务里，每个 item 创建后立刻 `bean.adjust_stock!(-quantity)`。
- **创建烘焙批次时加库存**：`after_create` 回调 `add_to_stock`，把 `roast_quantity_grams` 加到库存里。
- **生成配送单时扣库存**：给订阅生成配送单时，按订阅项的重量扣库存。
- **老板调整库存**：走 `adjust_stock!`，**是增量不是覆盖**。传正数加库存，传负数减库存，减到负数会报错。
- **取消配送单时加回库存**：把配送单的 `total_weight_grams` 加回库存。
- 所有库存变动都走 `adjust_stock!` 方法，不要直接改 `stock_grams` 字段。

### 3.4 优惠码规则
- **校验顺序（错了就对不上号）**：不存在 → 已停用 → 已过期 → 已用完 → 该用户已用过
- **大小写不敏感**：`welcome10` 和 `WELCOME10` 是同一个码（查询用 `UPPER(code) = UPPER(?)`，创建时自动转大写）
- **折扣计算**：
  - `fixed`：减固定金额，最多减到 0（不会负）
  - `percentage`：按百分比减（20 表示减 20% = 打 8 折）
- **并发安全**：`record_use!` 用了 `reload.lock!` 悲观行锁，加上数据库联合唯一索引，多线程同时点也不会超扣。
- **一人一码一次**：不管是订单用还是订阅用，同一个用户对同一个优惠码只能用一次，退了再订也不行。
- **订单和订阅不能分别用**：同一个码，用在订单了就不能再用在订阅，反之亦然。规则是 `user_id + promo_code` 全局唯一，不是按场景区分的。

---

## 四、代码结构

```
project186/
├── app.rb                          # Sinatra 主入口，helpers、序列化器
├── app/
│   ├── models/                     # 所有 ActiveRecord 模型
│   │   ├── user.rb
│   │   ├── address.rb
│   │   ├── coffee_bean.rb
│   │   ├── order.rb
│   │   ├── order_item.rb
│   │   ├── subscription.rb
│   │   ├── subscription_item.rb
│   │   ├── roast_batch.rb
│   │   ├── shipment.rb
│   │   ├── promotion_code.rb
│   │   └── promo_code_redemption.rb
│   ├── services/                   # 业务逻辑抽出来的服务类
│   │   ├── base_pricing.rb         # 价格计算 + 优惠码校验（核心）
│   │   ├── order/pricing.rb        # Order::Pricing < BasePricing
│   │   └── subscription/pricing.rb # Subscription::Pricing < BasePricing
│   └── routes/
│       ├── customer_api.rb         # 客户端接口
│       └── admin_api.rb            # 管理后台接口
├── db/
│   ├── migrate/                    # 数据库迁移（按时间戳排序）
│   └── schema.rb                   # 当前数据库结构
├── spec/
│   ├── models/                     # 模型单元测试
│   ├── services/                   # 服务类单元测试
│   ├── requests/                   # API 集成测试
│   └── spec_helper.rb
└── Gemfile
```

---

## 五、API 路由概览

### 公开接口（不用登录）
| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/coffee_beans` | 列出在售咖啡豆 |
| GET | `/api/coffee_beans/:id` | 咖啡豆详情 |
| POST | `/api/customers/register` | 客户注册 |

### 客户端接口（需要登录，header 传 `X-USER-ID`）
| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/customers/me` | 个人信息 |
| | **地址管理** | |
| GET | `/api/customers/me/addresses` | 我的地址列表 |
| POST | `/api/customers/me/addresses` | 新增地址 |
| PUT | `/api/customers/me/addresses/:id` | 修改地址（冻结的不能改） |
| PUT | `/api/customers/me/addresses/:id/default` | 设为默认 |
| DELETE | `/api/customers/me/addresses/:id` | 删除地址（冻结的不能删） |
| | **订单管理** | |
| GET | `/api/customers/me/orders` | 我的订单列表 |
| GET | `/api/customers/me/orders/:id` | 订单详情 |
| POST | `/api/customers/me/orders` | 下单（支持 promo_code 参数） |
| | **订阅管理** | |
| GET | `/api/customers/me/subscriptions` | 我的订阅列表 |
| GET | `/api/customers/me/subscriptions/:id` | 订阅详情 |
| POST | `/api/customers/me/subscriptions` | 开通订阅（支持 promo_code 参数） |
| PATCH | `/api/customers/me/subscriptions/:id/pause` | 暂停订阅 |
| PATCH | `/api/customers/me/subscriptions/:id/resume` | 恢复订阅 |
| PATCH | `/api/customers/me/subscriptions/:id/skip_next` | 跳过下次配送 |
| PATCH | `/api/customers/me/subscriptions/:id/cancel` | 取消订阅 |
| | **优惠码** | |
| POST | `/api/customers/me/validate_promo_code` | 预校验优惠码，返回折扣金额 |
| | **配送记录** | |
| GET | `/api/customers/me/shipments_history` | 历史收货记录 |

### 管理后台接口（需要 admin 权限）
| 方法 | 路径 | 说明 |
|---|---|---|
| | **咖啡豆管理** | |
| GET | `/api/admin/coffee_beans` | 所有咖啡豆 |
| GET | `/api/admin/coffee_beans/:id` | 详情 |
| POST | `/api/admin/coffee_beans` | 上新豆子 |
| PUT | `/api/admin/coffee_beans/:id` | 修改豆子信息 |
| PATCH | `/api/admin/coffee_beans/:id/adjust_stock` | 调整库存（增量） |
| PATCH | `/api/admin/coffee_beans/:id/activate` | 上架 |
| PATCH | `/api/admin/coffee_beans/:id/deactivate` | 下架 |
| | **烘焙批次** | |
| GET | `/api/admin/roast_batches` | 所有批次 |
| GET | `/api/admin/roast_batches/:id` | 批次详情（含关联的配送单） |
| POST | `/api/admin/roast_batches` | 新建烘焙批次（自动加库存） |
| | **配送单** | |
| GET | `/api/admin/shipments` | 所有配送单（可按状态/日期筛选） |
| GET | `/api/admin/shipments/:id` | 配送单详情 |
| POST | `/api/admin/shipments/generate_from_subscriptions` | 按烘焙批次生成配送单（核心操作） |
| POST | `/api/admin/shipments/:id/mark_shipped` | 标记已发货 |
| POST | `/api/admin/shipments/:id/mark_delivered` | 标记已送达 |
| POST | `/api/admin/shipments/:id/cancel` | 取消（自动回库存+回退订阅日期） |
| | **优惠码管理** | |
| GET | `/api/admin/promotion_codes` | 所有优惠码 |
| GET | `/api/admin/promotion_codes/valid` | 当前有效的优惠码 |
| GET | `/api/admin/promotion_codes/:id` | 详情（含使用统计） |
| POST | `/api/admin/promotion_codes` | 创建优惠码 |
| PUT | `/api/admin/promotion_codes/:id` | 修改优惠码 |
| PATCH | `/api/admin/promotion_codes/:id/activate` | 启用 |
| PATCH | `/api/admin/promotion_codes/:id/deactivate` | 停用 |
| | **其他** | |
| GET | `/api/admin/orders` | 所有订单 |
| GET | `/api/admin/orders/:id` | 订单详情 |
| GET | `/api/admin/subscriptions` | 所有订阅（可筛选） |
| GET | `/api/admin/subscriptions/upcoming` | 近期待配送订阅 |
| GET | `/api/admin/subscriptions/:id` | 订阅详情 |
| GET | `/api/admin/users` | 所有用户 |
| POST | `/api/admin/users/register_admin` | 新增管理员 |
| GET | `/api/admin/dashboard` | 数据看板（总数统计） |

---

## 六、开发小贴士

1. **登录机制**：没有 JWT，简单粗暴传 `X-USER-ID` header 就行，值是 user 的 id。测试里也是这么干的。
2. **事务边界**：下单、开订阅、生成配送单这三个操作都包在 `ActiveRecord::Base.transaction` 里，中间任何一步失败都会回滚，不会出现扣了库存但没订单的情况。
3. **价格计算统一走 Pricing**：`Order::Pricing` 和 `Subscription::Pricing` 是同一个逻辑，别在 controller 里自己算金额。
4. **跑测试**：`bundle exec rspec` 就行，138 个测试全绿才算过关。
5. **改业务规则先改测试**：尤其是优惠码、库存这种容易出边界 case 的地方。
6. **数据库是 SQLite**：不支持多线程并发写入，所以并发测试是用循环模拟的，生产环境换 PostgreSQL 就行。
