local __bundle = {}
local __cache = {}
local function require(name)
  if __cache[name] ~= nil then return __cache[name] end
  local loader = __bundle[name]
  if not loader then error("module not found: " .. tostring(name)) end
  local result = loader()
  __cache[name] = result
  return result
end
__bundle["domain.economy"] = function()
local Random = require("domain.random")

local Economy = {}

local GOODS = {
  { name = "抗原试纸", average_price = 90 },
  { name = "预制鸡块", average_price = 170 },
  { name = "微商面膜", average_price = 380 },
  { name = "蛋白粉罐", average_price = 720 },
  { name = "新风滤芯", average_price = 1500 },
  { name = "金豆金条", average_price = 3000 },
  { name = "X4 Pro", average_price = 7000 },
  { name = "老头乐车", average_price = 19000 },
}

local function positive_integer(value)
  return type(value) == "number" and value > 0 and value == math.floor(value)
end

local function pay(state, cost)
  local from_cash = math.min(state.cash, cost)
  state.cash = state.cash - from_cash
  state.deposit = state.deposit - (cost - from_cash)
end

local function inventory_index_for(state, goods_id)
  for index, item in ipairs(state.inventory) do
    if item.goods_id == goods_id then
      return index
    end
  end
  return nil
end

local function market_price_for(state, goods_id)
  for _, item in ipairs(state.market) do
    if item.goods_id == goods_id then
      return item.price
    end
  end
  return nil
end

function Economy.goods()
  local result = {}
  for i, item in ipairs(GOODS) do
    result[i] = {
      id = i,
      name = item.name,
      average_price = item.average_price,
    }
  end
  return result
end

function Economy.refresh_market(state, rng)
  local available = {}
  local market = {}

  for i = 1, #GOODS do
    available[i] = i
  end

  for slot = 1, 5 do
    local pick = Random.int(rng, 1, #available)
    local goods_id = table.remove(available, pick)
    local average_price = GOODS[goods_id].average_price
    local direction = Random.int(rng, 0, 1) == 0 and -1 or 1
    local variation = Random.next(rng) / 3
    market[slot] = {
      goods_id = goods_id,
      price = math.max(1, math.floor(average_price * (1 + direction * variation))),
    }
  end

  state.market = market
  return market
end

function Economy.advance_week(state)
  state.week = state.week + 1

  if state.week > state.week_limit then
    state.status = "lost"
    state.ending = "time_up"
    return { ok = false, reason = "time_up", week = state.week }
  end

  for i, price in ipairs(state.house_prices) do
    state.house_prices[i] = math.floor(price * 1.01)
  end
  state.deposit = math.floor(state.deposit * 1.005)
  Economy.refresh_market(state, state.rng)

  return { ok = true, week = state.week }
end

function Economy.buy(state, market_index, quantity)
  local offer = state.market[market_index]
  if offer == nil then
    return { ok = false, reason = "invalid_market_index" }
  end
  if not positive_integer(quantity) then
    return { ok = false, reason = "invalid_quantity" }
  end

  local inventory_index = inventory_index_for(state, offer.goods_id)
  if inventory_index == nil and #state.inventory >= 5 then
    return { ok = false, reason = "slot_limit" }
  end
  if state.used + quantity > state.capacity then
    return { ok = false, reason = "capacity_limit" }
  end

  local cost = offer.price * quantity
  if state.cash + state.deposit < cost then
    return { ok = false, reason = "insufficient_funds" }
  end

  pay(state, cost)
  if inventory_index == nil then
    state.inventory[#state.inventory + 1] = {
      goods_id = offer.goods_id,
      quantity = quantity,
      average_cost = offer.price,
    }
  else
    local item = state.inventory[inventory_index]
    item.average_cost = math.floor(
      (item.average_cost * item.quantity + cost) / (item.quantity + quantity)
    )
    item.quantity = item.quantity + quantity
  end
  state.used = state.used + quantity

  return { ok = true, cost = cost }
end

function Economy.sell(state, inventory_index, quantity)
  local item = state.inventory[inventory_index]
  if item == nil then
    return { ok = false, reason = "invalid_inventory_index" }
  end

  local price = market_price_for(state, item.goods_id)
  if price == nil then
    return { ok = false, reason = "not_in_market" }
  end
  if not positive_integer(quantity) then
    return { ok = false, reason = "invalid_quantity" }
  end
  if quantity > item.quantity then
    return { ok = false, reason = "insufficient_quantity" }
  end

  local revenue = price * quantity
  state.cash = state.cash + revenue
  state.used = state.used - quantity
  item.quantity = item.quantity - quantity

  if item.goods_id == 3 or item.goods_id == 7 then
    state.reputation = state.reputation - 1
  end
  if item.quantity == 0 then
    table.remove(state.inventory, inventory_index)
  end

  return { ok = true, revenue = revenue }
end

function Economy.deposit_all(state)
  state.deposit = state.deposit + state.cash
  state.cash = 0
  return { ok = true }
end

function Economy.withdraw_all(state)
  state.cash = state.cash + state.deposit
  state.deposit = 0
  return { ok = true }
end

function Economy.expand_capacity(state, amount)
  if not positive_integer(amount) then
    return { ok = false, reason = "invalid_amount" }
  end

  local cost = amount * 10000
  if state.cash + state.deposit < cost then
    return { ok = false, reason = "insufficient_funds" }
  end

  pay(state, cost)
  state.capacity = state.capacity + amount
  return { ok = true, cost = cost }
end

function Economy.treat(state)
  if state.health >= 100 then
    return { ok = false, reason = "health_full" }
  end

  local cost = (100 - state.health) * 5000
  if state.cash + state.deposit < cost then
    return { ok = false, reason = "insufficient_funds", cost = cost }
  end

  pay(state, cost)
  state.health = 100
  return { ok = true, cost = cost }
end

return Economy

end
__bundle["domain.events"] = function()
local Random = require("domain.random")

local Events = {}

local function scale(value, numerator, denominator)
  return math.floor(value * numerator / denominator)
end

function Events.price_event(state, rng)
  local roll = Random.next(rng)

  if roll < 0.10 then
    local down = Random.next(rng) < 0.5
    for i, price in ipairs(state.house_prices) do
      state.house_prices[i] = down and scale(price, 95, 100) or scale(price, 110, 100)
    end
    return { kind = down and "houses_all_down" or "houses_all_up" }
  end

  if roll < 0.15 then
    local index = Random.int(rng, 1, #state.house_prices)
    local down = Random.next(rng) < 0.5
    local price = state.house_prices[index]
    state.house_prices[index] = down and scale(price, 80, 100) or scale(price, 120, 100)
    return {
      kind = down and "house_single_down" or "house_single_up",
      house_id = index,
    }
  end

  if #state.market == 0 then
    return { kind = "none" }
  end

  local index = Random.int(rng, 1, #state.market)
  local up = Random.next(rng) < 0.5
  local offer = state.market[index]
  if up then
    offer.price = math.max(1, math.floor(offer.price * 3 + 0.5))
  else
    offer.price = math.max(1, math.floor(offer.price / 2))
  end
  return {
    kind = up and "goods_up" or "goods_down",
    goods_id = offer.goods_id,
  }
end

local GOODS_TEXTS = {
  [1] = {
    up = "    新毒株刷屏， 全网连夜下单， 抗原试纸严重断货。",
    down = "    砖家说：“已经流感化了， 不用天天测。” 过剩的抗原试纸出现滞销。",
  },
  [2] = {
    up = "    最新研究表明： 预制鸡块是优质蛋白的性价比之王， 预制鸡块供不应求。",
    down = "    禽流感病例再次出现， 全城下架活禽预制菜， 没人敢吃预制鸡块了。",
  },
  [3] = {
    up = "    直播间把微商面膜吹成逆龄神器， 粉丝连夜下单， 微商面膜价格上涨。",
    down = "    打假办突击微商仓库， 面膜被证三无， 微商面膜价格回落。",
  },
  [4] = {
    up = "    三胎政策再吹风， 健身宝妈抢蛋白粉， 蛋白粉罐价格一路上涨。",
    down = "    蛋白粉被检出工业氮， 蛋白粉罐价格下跌。",
  },
  [5] = {
    up = "    重度雾霾连续7天笼罩不散， 新风滤芯卖脱销了！",
    down = "    官方宣布优良天数创新高， 蓝天白云风景如画， 新风滤芯无人问津。",
  },
  [6] = {
    up = "    中国大妈掀起扫金热潮， 金豆金条价格飙涨！",
    down = "    美联储放话加息， 国际金价一路下跌， 金豆金条价格走低。",
  },
  [7] = {
    up = "    X4 Pro被黄牛炒上天， 加价到拿不到货， 新货供不应求！",
    down = "    官方说现货充足不支持黄牛， X4 Pro价格腰斩。",
  },
  [8] = {
    up = "    老头乐经销商说：“工厂产能不足， 提车必须加价！”",
    down = "    各地陆续禁止老头乐上路， 老头乐车销量下滑。",
  },
}

local HOUSE_TEXTS = {
  [1] = {
    down = "    夜市摊主收入提高， 临街单间显得太挤， 临街单间价格下跌20%。",
    up = "    租金太高的人改买小户， 临街单间价格上涨20%。",
  },
  [2] = {
    down = "    过户手续费上调， 巷口老屋成交冷清， 巷口老屋价格下跌20%。",
    up = "    旧房补贴到位， 巷口老屋被抢着看， 巷口老屋价格上涨20%。",
  },
  [3] = {
    down = "    灯市改建延期， 灯市小楼出现空置， 灯市小楼价格下跌20%。",
    up = "    刚需盯上中小户型， 灯市小楼价格上涨20%。",
  },
  [4] = {
    down = "    大户型税费传闻落地， 复式阁楼价格下跌20%。",
    up = "    大户型税费暂缓， 复式阁楼价格上涨20%。",
  },
  [5] = {
    down = "    连排被划进豪宅税范围， 连排小院价格下跌20%。",
    up = "    豪宅税暂缓执行， 连排小院价格上涨20%。",
  },
  [6] = {
    down = "    夜班收入下滑， 江岸雅居卖不动， 江岸雅居价格下跌20%。",
    up = "    新一批夜市股东套现买房， 江岸雅居价格上涨20%。",
  },
  [7] = {
    down = "    民间借贷风波蔓延， 城芯府邸看房的人少了， 城芯府邸价格下跌20%。",
    up = "    城区夜经济回暖， 城芯府邸价格上涨20%。",
  },
  [8] = {
    down = "    有钱人忙着迁居， 林间别院价格下跌20%。",
    up = "    热钱涌入度假房产， 林间别院价格上涨20%。",
  },
  [9] = {
    down = "    小岛产权说法不清， 海岛木屋价格下跌20%。",
    up = "    个人可购岛政策公布， 海岛木屋价格上涨20%。",
  },
  [10] = {
    down = "    科研报告说地球还早着呢， 星港居所价格下跌20%。",
    up = "    有人炒作百年内要换星球， 星港居所价格上涨20%。",
  },
}

local LIFE_TEXTS = {
  emergency_aid = "    我身无分文流落街头， 走投无路之际， 一个好心人看我可怜， 给了我3000块！",
  street_singer = "    我喜欢大街上卖唱小伙的歌， 忍不住掏了些钱给他。 现金减少5%！",
  minor_illness = "    飞涨的房价让我揪心。 健康减1！",
  petty_theft = "    双十一来临没管住手， 现金减少10%！",
  traffic_accident = "    为了多卖一点货， 赶路太急遭遇车祸。 健康减少3！",
  food_poisoning = "    商场打折我去抢购， 人太多挤得我喘不过气来。 健康减少2！",
  overwork = "    走路刷短视频没看路， 掉路边沟里了， 摔得我头破血流。 健康减少2！",
  major_theft = "    不小心落入传销陷阱， 幸好我找机会逃了出来， 现金减少15%！",
  bank_fee = "    银行： 小额账户要收管理费！ 存款减少1%！",
  fraud = "    开发商倒闭， 我的集资款全打了水漂。 现金减少20%！",
  poor_diet = "    为了攒首付每天只能喝白开泡面。 健康减1！",
  insomnia = "    我走在人行道上， 天上掉下一个花盆把我砸晕了。 健康减少1！",
  small_windfall = "    我突然想起两年前花500收的球星卡， 今天一看居然涨了100倍。 现金增加5万！",
  large_windfall = "    买彩票中了10万块！ 发啦！",
  bank_loss = "    遭遇金融危机， 百年银行倒闭！ 存款减少50%！",
  deposit_bonus = "    我用闲钱买了余额宝， 存款增加5%！",
  unexpected_expense = "    正骑着车呢， 一位大妈突然往我身上摔了过来。 现金减少10%！",
  found_money = "    我因为经常扶老奶奶过马路， 赢得了社区好青年称号， 现金增加1万！",
  hijack_reward = "    夜市遇到抢摊的， 我果断出手拦住， 摊主凑钱感谢见义勇为， 现金增加100万！",
}

function Events.price_text(event)
  if not event then return nil end
  if event.kind == "houses_all_down" then
    return "    夜市传开：“房产税要来了！”看房的人收住钱包， 房价下跌5%。"
  end
  if event.kind == "houses_all_up" then
    return "    有人在灯市喊：“这城的房子十年内只会涨！” 房价上涨10%。"
  end
  if event.kind == "house_single_up" or event.kind == "house_single_down" then
    local house = HOUSE_TEXTS[event.house_id]
    return house and house[event.kind == "house_single_up" and "up" or "down"] or nil
  end
  if event.kind == "goods_up" or event.kind == "goods_down" then
    local goods = GOODS_TEXTS[event.goods_id]
    return goods and goods[event.kind == "goods_up" and "up" or "down"] or nil
  end
  return nil
end

function Events.life_text(id)
  return LIFE_TEXTS[id]
end

function Events.death_text()
  return "    一个漆黑寒冷的夜晚， 我再次晕倒在街头。 长期的白开泡面和揪心的房价摧毁了我的健康， 让我再也没能醒过来。。。"
end

function Events.blackout_text(aid)
  if not aid or aid.kind == "unaffordable" then
    return "    我由于劳累过度晕倒在街头， 没有一个人敢来扶我。 健康减少1！"
  end
  return "    我由于劳累过度晕倒在街头， 好心人送我去了医院， 花掉急救费" .. tostring(aid.cost) .. "元！"
end

local LIFE_EVENTS = {
  { last = 13, id = "street_singer", target = "cash", numerator = 95, denominator = 100 },
  { last = 27, id = "minor_illness", target = "health", delta = -1 },
  { last = 41, id = "petty_theft", target = "cash", numerator = 90, denominator = 100 },
  { last = 55, id = "traffic_accident", target = "health", delta = -3 },
  { last = 69, id = "food_poisoning", target = "health", delta = -2 },
  { last = 83, id = "overwork", target = "health", delta = -2 },
  { last = 97, id = "major_theft", target = "cash", numerator = 85, denominator = 100 },
  { last = 111, id = "bank_fee", target = "deposit", numerator = 99, denominator = 100 },
  { last = 125, id = "fraud", target = "cash", numerator = 80, denominator = 100 },
  { last = 139, id = "poor_diet", target = "health", delta = -1 },
  { last = 153, id = "insomnia", target = "health", delta = -1 },
  { last = 158, id = "small_windfall", target = "cash", delta = 50000 },
  { last = 163, id = "large_windfall", target = "cash", delta = 100000 },
  { last = 168, id = "bank_loss", target = "deposit", numerator = 50, denominator = 100 },
  { last = 182, id = "deposit_bonus", target = "deposit", numerator = 105, denominator = 100 },
  { last = 196, id = "unexpected_expense", target = "cash", numerator = 90, denominator = 100 },
  { last = 201, id = "found_money", target = "cash", delta = 10000 },
  { last = 202, id = "hijack_reward", target = "cash", delta = 1000000 },
}

function Events.life_event(state, rng)
  if #state.inventory == 0 and state.cash + state.deposit < 500 then
    state.cash = state.cash + 3000
    return { id = "emergency_aid" }
  end

  local point = math.floor(Random.next(rng) * 1000)
  for _, event in ipairs(LIFE_EVENTS) do
    if point <= event.last then
      if event.numerator ~= nil then
        state[event.target] = scale(state[event.target], event.numerator, event.denominator)
      else
        state[event.target] = state[event.target] + event.delta
      end
      return { id = event.id }
    end
  end

  return { id = "none" }
end

function Events.sickness(state, rng)
  local point = math.floor(Random.next(rng) * 100)
  local health = state.health

  if health < 95 and point < 95 - health then
    return "dead"
  end
  if point < 100 - health then
    return "blackout"
  end
  return "none"
end

function Events.apply_blackout_aid(state)
  local missing_health = 100 - state.health
  local full_cost = missing_health * 10000

  if state.cash >= full_cost then
    state.cash = state.cash - full_cost
    state.health = 100
    return { ok = true, kind = "full", recovered = missing_health, cost = full_cost }
  end

  local recovered = math.floor(state.cash / 10000)
  if recovered > 0 then
    local cost = recovered * 10000
    state.cash = state.cash - cost
    state.health = state.health + recovered
    return { ok = true, kind = "partial", recovered = recovered, cost = cost }
  end

  state.health = state.health - 1
  return { ok = false, kind = "unaffordable", recovered = -1, cost = 0 }
end

return Events

end
__bundle["domain.game_state"] = function()
local Economy = require("domain.economy")
local Houses = require("domain.houses")
local Random = require("domain.random")

local State = {}

function State.new(seed)
  local rng = Random.new(seed)
  local house_prices = {}
  for i, house in ipairs(Houses.catalog()) do
    house_prices[i] = house.base_price
  end

  local state = {
    week = 1,
    week_limit = 52,
    cash = 3000,
    deposit = 0,
    health = 100,
    reputation = 100,
    capacity = 100,
    used = 0,
    inventory = {},
    market = {},
    house_prices = house_prices,
    selected_house = 1,
    status = "playing",
    ending = nil,
    rng = rng,
  }

  Economy.refresh_market(state, rng)
  return state
end

return State

end
__bundle["domain.houses"] = function()
local Random = require("domain.random")

local Houses = {}
local OFFICE_METADATA = setmetatable({}, { __mode = "k" })
local ACTIVE_OFFICES = setmetatable({}, { __mode = "k" })

local CATALOG = {
  { name = "临街单间", base_price = 400000 },
  { name = "巷口老屋", base_price = 1200000 },
  { name = "灯市小楼", base_price = 2400000 },
  { name = "复式阁楼", base_price = 4000000 },
  { name = "连排小院", base_price = 6000000 },
  { name = "江岸雅居", base_price = 10000000 },
  { name = "城芯府邸", base_price = 20000000 },
  { name = "林间别院", base_price = 50000000 },
  { name = "海岛木屋", base_price = 100000000 },
  { name = "星港居所", base_price = 300000000 },
}

function Houses.catalog()
  local result = {}
  for i, house in ipairs(CATALOG) do
    result[i] = {
      id = i,
      name = house.name,
      base_price = house.base_price,
    }
  end
  return result
end

function Houses.reputation_allows(state, roll)
  local point = math.floor(roll * 50)
  return point >= 100 - state.reputation
end

function Houses.open_office(state, rng)
  local office = {}
  local allowed = {}
  for house_index = 1, #CATALOG do
    allowed[house_index] = Houses.reputation_allows(state, Random.next(rng))
  end
  OFFICE_METADATA[office] = { state = state, allowed = allowed }
  ACTIVE_OFFICES[state] = office
  return office
end

local function office_metadata(state, office)
  if type(office) ~= "table" then
    return nil
  end
  local metadata = OFFICE_METADATA[office]
  if metadata == nil
      or not rawequal(metadata.state, state)
      or not rawequal(ACTIVE_OFFICES[state], office) then
    return nil
  end
  return metadata
end

function Houses.can_buy(state, house_index, office)
  if type(house_index) ~= "number"
      or house_index ~= math.floor(house_index)
      or CATALOG[house_index] == nil
      or state.house_prices[house_index] == nil then
    return { ok = false, reason = "invalid_house_index" }
  end
  if state.status ~= "playing" then
    return { ok = false, reason = "not_playing" }
  end
  local metadata = office_metadata(state, office)
  if metadata == nil then
    return { ok = false, reason = "invalid_office" }
  end

  local price = state.house_prices[house_index]
  if state.cash + state.deposit < price then
    return { ok = false, reason = "insufficient_funds" }
  end
  if metadata.allowed[house_index] ~= true then
    return { ok = false, reason = "reputation_rejected" }
  end

  return { ok = true, price = price }
end

function Houses.buy(state, house_index, purchased_at, office)
  local result = Houses.can_buy(state, house_index, office)
  if not result.ok then
    return result
  end

  local from_cash = math.min(state.cash, result.price)
  state.cash = state.cash - from_cash
  state.deposit = state.deposit - (result.price - from_cash)
  state.selected_house = house_index
  state.status = "won"
  state.ending = "house_bought"

  return {
    ok = true,
    house_id = house_index,
    price = result.price,
    purchased_at = purchased_at,
  }
end

return Houses

end
__bundle["domain.random"] = function()
local Random = {}

local MODULUS = 2147483647
local MULTIPLIER = 48271
local Q = math.floor(MODULUS / MULTIPLIER)
local R = MODULUS % MULTIPLIER

local function copy_forced_rolls(forced_rolls)
  if forced_rolls == nil then
    return {}
  end
  if type(forced_rolls) ~= "table" then
    error("forced_rolls must be an array table", 3)
  end

  local count = 0
  local maximum_index = 0
  for key, value in pairs(forced_rolls) do
    if type(key) ~= "number" or key <= 0 or key ~= math.floor(key) then
      error("forced_rolls keys must be positive integers", 3)
    end
    if type(value) ~= "number"
        or value ~= value
        or value == math.huge
        or value == -math.huge
        or value < 0
        or value >= 1 then
      error("forced_rolls values must be finite numbers in [0, 1)", 3)
    end
    count = count + 1
    maximum_index = math.max(maximum_index, key)
  end

  if count ~= maximum_index then
    error("forced_rolls must not contain sparse entries", 3)
  end

  local forced = {}
  for i = 1, maximum_index do
    if rawget(forced_rolls, i) == nil then
      error("forced_rolls must not contain sparse entries", 3)
    end
    forced[i] = forced_rolls[i]
  end
  return forced
end

local function finite_index(value)
  return type(value) == "number" and value == math.floor(value) and value >= 1
end

function Random.sanitize(rng)
  if type(rng) ~= "table" then return rng end
  local state = tonumber(rng.state)
  if state == nil or state ~= state or state == math.huge or state == -math.huge then
    rng.state = 1
    return rng
  end
  state = math.floor(state + 0.5)
  state = state % MODULUS
  if state <= 0 then state = state + MODULUS end
  if state >= MODULUS then state = 1 end
  rng.state = state
  if not finite_index(rng.forced_index) then rng.forced_index = 1 end
  if type(rng.forced_rolls) ~= "table" then rng.forced_rolls = {} end
  return rng
end

function Random.new(seed, forced_rolls)
  local normalized = math.floor(tonumber(seed) or 1) % MODULUS
  if normalized <= 0 then
    normalized = normalized + MODULUS - 1
  end

  return Random.sanitize({
    state = normalized,
    forced_rolls = copy_forced_rolls(forced_rolls),
    forced_index = 1,
  })
end

function Random.next(rng)
  Random.sanitize(rng)
  local forced = rng.forced_rolls[rng.forced_index]
  if forced ~= nil then
    rng.forced_index = rng.forced_index + 1
    if forced < 0 then return 0 end
    if forced >= 1 then return 0.9999999999999999 end
    return forced
  end
  local hi = math.floor(rng.state / Q)
  local lo = rng.state - hi * Q
  local test = MULTIPLIER * lo - R * hi
  if test <= 0 then test = test + MODULUS end
  rng.state = test
  return rng.state / MODULUS
end

function Random.int(rng, minimum, maximum)
  local roll = Random.next(rng)
  if roll < 0 then
    roll = 0
  elseif roll >= 1 then
    roll = 0.9999999999999999
  end
  return minimum + math.floor(roll * (maximum - minimum + 1))
end

return Random

end
__bundle["domain.save"] = function()
local Save = {}

local VERSION = 1

local function deep_copy(value, seen)
  if type(value) ~= "table" then
    return value
  end

  seen = seen or {}
  if seen[value] ~= nil then
    return seen[value]
  end

  local copy = {}
  seen[value] = copy
  for key, child in pairs(value) do
    copy[deep_copy(key, seen)] = deep_copy(child, seen)
  end
  return copy
end

function Save.default_records()
  local houses = {}
  for i = 1, 10 do
    houses[i] = {
      first_success_at = "从未成功",
      success_count = 0,
    }
  end

  return {
    version = VERSION,
    houses = houses,
    total_successes = 0,
    best_house = -1,
  }
end

local function nonnegative_integer(value)
  return type(value) == "number"
    and value >= 0
    and value == math.floor(value)
    and value < math.huge
end

local function valid_best_house(value)
  return value == -1
    or (type(value) == "number"
      and value >= 1
      and value <= 10
      and value == math.floor(value))
end

local function records_are_valid(records)
  if type(records) ~= "table"
      or type(records.houses) ~= "table"
      or not nonnegative_integer(records.total_successes)
      or not valid_best_house(records.best_house) then
    return false
  end

  for i = 1, 10 do
    local house = records.houses[i]
    if type(house) ~= "table"
        or type(house.first_success_at) ~= "string"
        or not nonnegative_integer(house.success_count) then
      return false
    end
  end
  return true
end

function Save.record_success(records, house_index, succeeded_at)
  if not records_are_valid(records) or type(succeeded_at) ~= "string" then
    return { ok = false, reason = "invalid_records" }
  end
  if type(house_index) ~= "number"
      or house_index ~= math.floor(house_index)
      or house_index < 1
      or house_index > 10 then
    return { ok = false, reason = "invalid_house_index" }
  end

  local house = records.houses[house_index]
  if house.success_count == 0 then
    house.first_success_at = succeeded_at
  end
  house.success_count = house.success_count + 1
  records.total_successes = records.total_successes + 1
  if records.best_house == -1 or house_index > records.best_house then
    records.best_house = house_index
  end

  return { ok = true }
end

function Save.encode(records)
  return {
    version = VERSION,
    records = deep_copy(records),
  }
end

local function source_and_version(encoded)
  if type(encoded) ~= "table" then
    return nil, nil
  end

  local source = encoded
  if encoded.records ~= nil then
    if type(encoded.records) ~= "table" then
      return nil, nil
    end
    source = encoded.records
  end

  local version = encoded.version
  if version == nil then
    version = source.version
  end
  if version == nil then
    version = 0
  end
  if type(version) ~= "number"
      or version ~= math.floor(version)
      or version < 0
      or version > VERSION then
    return nil, nil
  end
  return source, version
end

function Save.decode(encoded)
  local records = Save.default_records()
  local source = source_and_version(encoded)
  if source == nil then
    return records
  end

  if type(source.houses) == "table" then
    for i = 1, 10 do
      local house_source = rawget(source.houses, i)
      if house_source == nil then
        house_source = rawget(source.houses, tostring(i))
      end
      if type(house_source) == "table" then
        if type(house_source.first_success_at) == "string" then
          records.houses[i].first_success_at = house_source.first_success_at
        end
        if nonnegative_integer(house_source.success_count) then
          records.houses[i].success_count = house_source.success_count
        end
      end
    end
  end

  if nonnegative_integer(source.total_successes) then
    records.total_successes = source.total_successes
  end
  if valid_best_house(source.best_house) then
    records.best_house = source.best_house
  end
  return records
end

return Save

end
__bundle["ui.layout"] = function()
local Layout = {}

local function action(id, x, y, w, h, label, disabled)
  return {
    id = id, x = x, y = y, w = w, h = h,
    label = label, disabled = disabled or nil,
  }
end

local function copy_actions(source)
  local out = {}
  for index, item in ipairs(source) do
    out[index] = action(
      item.id, item.x, item.y, item.w, item.h, item.label, item.disabled
    )
  end
  return out
end

-- Task 1 locks interactive rectangles and coarse regions only.
-- Task 3 adds labels and the remaining noninteractive visual fields.
-- These are 360x600 logical rectangles scaled component-wise with
-- floor(value * 4 / 3 + 0.5); the golden fixture retains logical provenance.
-- X4P portrait is locked to 480x800; ctx.screen.width/height stay 480/800.
Layout.MAIN = {
  market = { x = 0, y = 92, w = 205, h = 255 },
  warehouse = { x = 205, y = 92, w = 275, h = 255 },
  status_cash = { x = 0, y = 351, w = 480, h = 43 },
  status_deposit = { x = 0, y = 399, w = 480, h = 43 },
}

Layout.MAIN_VISUAL = {
  header = { x = 0, y = 0, w = 480, h = 60 },
  header_house_label = { x = 13, y = 18 },
  header_house_value = { x = 96, y = 18 },
  header_time_label = { x = 300, y = 18 },
  header_time_value = { x = 383, y = 18 },
  market_title = { x = 103, y = 92 },
  warehouse_title = { x = 343, y = 92 },
  column_y = 120,
  market_goods = { x = 27, y = 120 },
  market_price = { x = 113, y = 120 },
  warehouse_goods = { x = 232, y = 120 },
  warehouse_price = { x = 307, y = 120 },
  warehouse_quantity = { x = 387, y = 120 },
  market_price_box = { x = 100, y = 147, w = 69, h = 40 },
  warehouse_price_box = { x = 305, y = 147, w = 69, h = 40 },
  warehouse_quantity_box = { x = 375, y = 147, w = 69, h = 40 },
  slot_step = 40,
  slot_text_y_offset = 8,
  status_cash_label = { x = 13, y = 360 },
  status_cash_value = { x = 92, y = 360 },
  status_health_label = { x = 288, y = 360 },
  status_health_value = { x = 367, y = 360 },
  status_deposit_label = { x = 13, y = 408 },
  status_deposit_value = { x = 92, y = 408 },
  status_reputation_label = { x = 288, y = 408 },
  status_reputation_value = { x = 367, y = 408 },
}

-- Resolved from the original 360x600 Android activities, then scaled
-- component-wise by 4/3. android-activity-layout.golden.json preserves the
-- source XML hashes and raw constraints used to derive these rectangles.
Layout.ACTIVITIES = {
  story = {
    text = { x = 40, y = 67, w = 400, h = 147 },
    continue = { x = 327, y = 227, w = 100, h = 51 },
    start = { x = 107, y = 227, w = 267, h = 51 },
  },
  help = {
    leave = { x = 11, y = 740, w = 133, h = 60 },
    next = { x = 336, y = 740, w = 133, h = 60 },
    highlights = {
      { x = 0, y = 0, w = 480, h = 60 },
      { x = 0, y = 60, w = 205, h = 291 },
      { x = 205, y = 60, w = 275, h = 291 },
      { x = 0, y = 351, w = 480, h = 92 },
      { x = 0, y = 633, w = 480, h = 60 },
      { x = 0, y = 687, w = 120, h = 60 },
      { x = 120, y = 687, w = 120, h = 60 },
      { x = 240, y = 687, w = 120, h = 60 },
      { x = 360, y = 687, w = 120, h = 60 },
    },
    explanation = { x = 40, y = 460, w = 400, h = 160, lineHeight = 24 },
  },
  houses = {
    head = { x = 0, y = 0, w = 480, h = 96 },
    title = { x = 240, y = 13 },
    money = { x = 13, y = 63 },
    viewport = { x = 0, y = 96, w = 480, h = 622 },
    visibleCount = 2,
    pageCount = 5,
    rows = {
      { x = 0, y = 96, w = 480, h = 311 },
      { x = 0, y = 407, w = 480, h = 311 },
    },
    rowFields = {
      image = { x = 5, y = 3, w = 253, h = 212 },
      selection = { x = 264, y = 0, w = 163, h = 53 },
      name = { x = 264, y = 13, w = 163, h = 32 },
      price = { x = 264, y = 53, w = 211, h = 32 },
      purchased = { x = 427, y = 53, w = 48, h = 32 },
      description = { x = 264, y = 99, w = 211, h = 104 },
    },
    buy = { x = 67, y = 745, w = 67, h = 39 },
    prev = { x = 142, y = 745, w = 96, h = 39 },
    next = { x = 246, y = 745, w = 96, h = 39 },
    leave = { x = 347, y = 745, w = 67, h = 39 },
  },
  records = {
    head = { x = 0, y = 0, w = 480, h = 267 },
    title = { x = 240, y = 13 },
    columnsY = 63,
    columnWidths = { 184, 184, 112 },
    rows = {
      { x = 0, y = 88, w = 480, h = 59 },
      { x = 0, y = 147, w = 480, h = 59 },
      { x = 0, y = 205, w = 480, h = 59 },
      { x = 0, y = 264, w = 480, h = 59 },
      { x = 0, y = 323, w = 480, h = 59 },
      { x = 0, y = 381, w = 480, h = 59 },
      { x = 0, y = 440, w = 480, h = 59 },
      { x = 0, y = 499, w = 480, h = 59 },
      { x = 0, y = 557, w = 480, h = 59 },
      { x = 0, y = 616, w = 480, h = 59 },
    },
    leave = { x = 207, y = 745, w = 67, h = 39 },
  },
}

-- 设备字体只有 24px，用加高描边按钮占满行情区空白；顶行仍锚在 XML 的 147。
-- 状态栏绘制在 二手市场 上方 8px（y=508），五行均分 147..500。
-- 货名最长是「X4 Pro」79px，150-44=106 绰绰有余；别放 5 个汉字以上的名字。
Layout.GOODS_SLOTS = {
  first_y = 147,
  w = 150,
  h = 70,
  step = 70,
  art_w = 135,
  art_h = 54,
  sell_x = 232,
  sell_w = 240,
}

-- 底图旧竖线在 x≈200；新线在价格右缘 225 与仓库按钮 232 之间晃动。
Layout.COLUMN_DIVIDER = {
  x = 228,
  y = 92,
  bottom = 508,
  erase = { x = 197, y = 90, w = 8, h = 365 },
}

Layout.GOODS_LIST = {
  market_goods = { x = 48, y = 120 },
  market_price = { x = 164, y = 120 },
  warehouse_goods = { x = 272, y = 120 },
  warehouse_price = { x = 328, y = 120 },
  warehouse_quantity = { x = 416, y = 120 },
  market_price_box = { x = 150, y = 147, w = 75, h = 60 },
  -- 买入价右缘、数量右缘。名字单独占上一行，数字在下一行，避免四字货名压住价格。
  warehouse_price_right = 400,
  warehouse_quantity_right = 464,
  warehouse_name_y = 6,
  warehouse_value_y = 38,
}

local main_actions = {}

for index = 1, 5 do
  main_actions[#main_actions + 1] = action(
    "buy_" .. index,
    Layout.MAIN.market.x,
    Layout.GOODS_SLOTS.first_y + (index - 1) * Layout.GOODS_SLOTS.step,
    Layout.GOODS_SLOTS.w,
    Layout.GOODS_SLOTS.h,
    "买入"
  )
end

for index = 1, 5 do
  main_actions[#main_actions + 1] = action(
    "sell_" .. index,
    Layout.GOODS_SLOTS.sell_x,
    Layout.GOODS_SLOTS.first_y + (index - 1) * Layout.GOODS_SLOTS.step,
    Layout.GOODS_SLOTS.sell_w,
    Layout.GOODS_SLOTS.h,
    "卖出"
  )
end

-- 三行底栏不再重叠：行高 56、缝 8，命中盒与绘制同一套从上到下的矩形。
main_actions[#main_actions + 1] = action("market1", 13, 592, 133, 56, "二手市场")
main_actions[#main_actions + 1] = action("market2", 173, 592, 133, 56, "农贸市场")
main_actions[#main_actions + 1] = action("market3", 333, 592, 133, 56, "批发市场")
main_actions[#main_actions + 1] = action("bank", 9, 656, 100, 56, "银行")
main_actions[#main_actions + 1] = action("hospital", 129, 656, 100, 56, "医院")
main_actions[#main_actions + 1] = action("houses", 249, 656, 100, 56, "售楼部")
main_actions[#main_actions + 1] = action("agency", 369, 656, 100, 56, "中介")
main_actions[#main_actions + 1] = action("help", 13, 720, 133, 56, "帮助")
main_actions[#main_actions + 1] = action("start_game", 173, 720, 133, 56, "开始游戏")
main_actions[#main_actions + 1] = action("records", 333, 720, 133, 56, "历程表")

Layout.MAIN_ACTIONS = copy_actions(main_actions)

local function main_action_rect(id)
  for _, item in ipairs(Layout.MAIN_ACTIONS) do
    if item.id == id then
      return { x = item.x, y = item.y, w = item.w, h = item.h }
    end
  end
end

function Layout.status_band()
  local cash = Layout.MAIN.status_cash
  local deposit = Layout.MAIN.status_deposit
  local band_h = deposit.y + deposit.h - cash.y
  local markets = main_action_rect("market1")
  local shift = markets.y - 8 - band_h - cash.y
  return {
    x = 0,
    y = cash.y + shift,
    w = 480,
    h = band_h,
    shift = shift,
  }
end

function Layout.help_highlights()
  local header = Layout.MAIN_VISUAL.header
  local band = Layout.status_band()
  local columns_y = Layout.COLUMN_DIVIDER.y
  local columns_h = band.y - columns_y
  local divider_x = Layout.COLUMN_DIVIDER.x
  local market1 = main_action_rect("market1")
  local market3 = main_action_rect("market3")
  return {
    { x = header.x, y = header.y, w = header.w, h = header.h },
    { x = 0, y = columns_y, w = divider_x, h = columns_h },
    { x = divider_x, y = columns_y, w = 480 - divider_x, h = columns_h },
    { x = band.x, y = band.y, w = band.w, h = band.h },
    {
      x = market1.x,
      y = market1.y,
      w = market3.x + market3.w - market1.x,
      h = market1.h,
    },
    main_action_rect("bank"),
    main_action_rect("hospital"),
    main_action_rect("houses"),
    main_action_rect("agency"),
  }
end

Layout.ACTIVITIES.help.highlights = Layout.help_highlights()

function Layout.actions(saved)
  local screen = saved.screen
  if screen == "main" then
    local out = copy_actions(main_actions)
    local playing = saved.game ~= nil and saved.game.status == "playing"
    local inventory_count = playing and #saved.game.inventory or 0
    for _, item in ipairs(out) do
      local buy_index = tonumber(string.match(item.id, "^buy_(%d+)$"))
      local sell_index = tonumber(string.match(item.id, "^sell_(%d+)$"))
      local market_index = tonumber(string.match(item.id, "^market(%d+)$"))
      if buy_index then
        item.disabled = not playing
      elseif sell_index then
        item.disabled = not playing or sell_index > inventory_count
      elseif market_index then
        item.disabled = not playing or market_index == saved.current_market
      elseif item.id == "bank" or item.id == "hospital"
          or item.id == "houses" or item.id == "agency" then
        item.disabled = not playing
      elseif item.id == "start_game" then
        item.label = playing and "结束游戏" or "开始游戏"
      end
    end
    if not playing then
      local lobby = {
        start_game = { x = 40, y = 392, w = 400, h = 88 },
        help = { x = 40, y = 680, w = 188, h = 64 },
        records = { x = 252, y = 680, w = 188, h = 64 },
      }
      local picked = {}
      for _, id in ipairs({ "start_game", "help", "records" }) do
        for _, item in ipairs(out) do
          if item.id == id then
            local box = lobby[id]
            item.x, item.y, item.w, item.h = box.x, box.y, box.w, box.h
            picked[#picked + 1] = item
          end
        end
      end
      return picked
    end
    return out
  elseif screen == "story" then
    if (saved.story_step or 1) >= 5 then
      local rect = Layout.ACTIVITIES.story.start
      return { action("finish_story", rect.x, rect.y, rect.w, rect.h, "开始挑战") }
    end
    local rect = Layout.ACTIVITIES.story.continue
    return { action("continue_story", rect.x, rect.y, rect.w, rect.h, "继续") }
  elseif screen == "houses" then
    local page = Layout.ACTIVITIES.houses
    local start = Layout.house_page_start(saved)
    return {
      action("house_buy", page.buy.x, page.buy.y, page.buy.w, page.buy.h, "购买"),
      action("house_prev", page.prev.x, page.prev.y, page.prev.w, page.prev.h, "上一页", start <= 1),
      action("house_next", page.next.x, page.next.y, page.next.w, page.next.h, "下一页", start >= 9),
      action("return_main", page.leave.x, page.leave.y, page.leave.w, page.leave.h, "离开"),
    }
  elseif screen == "records" then
    local rect = Layout.ACTIVITIES.records.leave
    return {
      action("return_main", rect.x, rect.y, rect.w, rect.h, "离开"),
    }
  elseif screen == "help" then
    local page = Layout.ACTIVITIES.help
    local last = (saved.help_step or 1) >= 9
    local next_btn = action(
      last and "return_main" or "help_next",
      page.next.x, page.next.y, page.next.w, page.next.h,
      last and "完成" or "下一步"
    )
    return {
      next_btn,
      action("return_main", page.leave.x, page.leave.y, page.leave.w, page.leave.h, "离开"),
    }
  end
  return {}
end

function Layout.house_page_start(saved)
  local index = math.max(1, math.min(9, (saved and saved.house_scroll) or 1))
  return math.floor((index - 1) / 2) * 2 + 1
end

function Layout.house_rows(saved)
  local page = Layout.ACTIVITIES.houses
  local first = Layout.house_page_start(saved)
  local rows = {}
  for slot, rect in ipairs(page.rows) do
    rows[slot] = {
      id = "house_row_" .. tostring(first + slot - 1),
      house_index = first + slot - 1,
      x = rect.x, y = rect.y, w = rect.w, h = rect.h,
    }
  end
  return rows
end

-- Trade dialogs keep a shortcut row inside the modal so it does not cover
-- the main-screen footer.  Buttons use the same 100x52 paper style as bank.
local QTY_ROW_HEIGHT = 36
-- 买入/卖出盖住行情区，现金和数量都画在这张卡片里面。
local TRADE_FRAME = { x = 0, y = 60, w = 480, h = 500 }
local SERVICE_BTN = { w = 100, h = 52 }
local QTY_BTN = { w = 72, h = 72 }
local TRADE_QTY_Y = 320
local TRADE_BTN_Y = 444
local TRADE_SHORTCUT_Y = 404

-- 所有对话弹层共用同一张豆包出的满宽纸卡（480x264，卡面 427..691）：
-- 双层边框 + 四角铆钉 + 左上挂牌，牌里写标题，右上角留给现金/存款，
-- 正文压在挂牌下面，按钮固定在 605..657。整卡左右到边，不再露出被切一半的
-- 图标；现金/存款也搬进卡内，不再有浮在卡外、缝隙里漏行情字的那条横条。
-- 注意：这份文件的主 chunk 已经接近 Lua 的 200 个 local 上限，再往主 chunk 里
-- 加 local 会让后面 global 函数里的同名引用退化成全局变量（运行时 nil）。
-- 卡面几何因此挂在全局 CARD 表上，不占 local 名额。
CARD = {
  frame = { x = 0, y = 427, w = 480, h = 264 },
  plate = { cx = 89, y = 449 },
  funds = { right = 456, y = 449, w = 286 },
  text = { x = 24, y = 490, w = 432, lineHeight = 26, maxLines = 4 },
  btnY = 605,
  dashY = 565,
  -- 买卖卡是 480x500 的竖版纸卡（60..560），挂牌在卡头顶部正中，
  -- 资金行压在挂牌下面一行，商品图和文字从 168 开始。
  trade = { plate = { cx = 240, y = 95 }, fundsY = 138, pictureY = 168 },
}
local CARD_FRAME = CARD.frame
local CARD_PLATE = CARD.plate
local CARD_FUNDS = CARD.funds
local CARD_TEXT = CARD.text
local CARD_BTN_Y = CARD.btnY
local CARD_DASH_Y = CARD.dashY
local SERVICE_BTN_Y = CARD_BTN_Y

-- 中介卡沿用同一个卡面：牌里写「中介」，资金跟在标题行右侧，数量行用 44 高的
-- 加减按钮，快捷数量条落在 565 那条虚线位置。
local AGENCY_FRAME = { x = CARD_FRAME.x, y = CARD_FRAME.y, w = CARD_FRAME.w, h = CARD_FRAME.h }
local AGENCY_STEPPER = { y = 481, w = 44, h = 44 }
local AGENCY_CHIP = { y = CARD_DASH_Y, w = 68, h = 32, gap = 6 }
local AGENCY_BTN_Y = CARD_BTN_Y

-- 备注卡（行情/人生/昏倒/终局/名声）也走同一张纸卡：标题写进挂牌，正文自动
-- 换行，实心「确认」在卡底；整张卡仍是点击热区。
local NOTE_FRAME = { x = CARD_FRAME.x, y = CARD_FRAME.y, w = CARD_FRAME.w, h = CARD_FRAME.h }

local overlay_frames = {
  new_game = { x = CARD_FRAME.x, y = CARD_FRAME.y, w = CARD_FRAME.w, h = CARD_FRAME.h },
  quit_game = { x = CARD_FRAME.x, y = CARD_FRAME.y, w = CARD_FRAME.w, h = CARD_FRAME.h },
  buy_goods = { x = TRADE_FRAME.x, y = TRADE_FRAME.y, w = TRADE_FRAME.w, h = TRADE_FRAME.h },
  sell_goods = { x = TRADE_FRAME.x, y = TRADE_FRAME.y, w = TRADE_FRAME.w, h = TRADE_FRAME.h },
  bank = { x = CARD_FRAME.x, y = CARD_FRAME.y, w = CARD_FRAME.w, h = CARD_FRAME.h },
  hospital = { x = CARD_FRAME.x, y = CARD_FRAME.y, w = CARD_FRAME.w, h = CARD_FRAME.h },
  agency = { x = AGENCY_FRAME.x, y = AGENCY_FRAME.y, w = AGENCY_FRAME.w, h = AGENCY_FRAME.h },
  price_note = { x = NOTE_FRAME.x, y = NOTE_FRAME.y, w = NOTE_FRAME.w, h = NOTE_FRAME.h },
  life_note = { x = NOTE_FRAME.x, y = NOTE_FRAME.y, w = NOTE_FRAME.w, h = NOTE_FRAME.h },
  sick_blackout = { x = NOTE_FRAME.x, y = NOTE_FRAME.y, w = NOTE_FRAME.w, h = NOTE_FRAME.h },
  sick_dead = { x = NOTE_FRAME.x, y = NOTE_FRAME.y, w = NOTE_FRAME.w, h = NOTE_FRAME.h },
  time_up = { x = NOTE_FRAME.x, y = NOTE_FRAME.y, w = NOTE_FRAME.w, h = NOTE_FRAME.h },
  sell_reputation = { x = NOTE_FRAME.x, y = NOTE_FRAME.y, w = NOTE_FRAME.w, h = NOTE_FRAME.h },
  no_money = { x = CARD_FRAME.x, y = CARD_FRAME.y, w = CARD_FRAME.w, h = CARD_FRAME.h },
  status = { x = CARD_FRAME.x, y = CARD_FRAME.y, w = CARD_FRAME.w, h = CARD_FRAME.h },
  buy_succ = { x = 47, y = 160, w = 387, h = 480 },
}

-- 对话类弹层（开始/结束/银行/医院/备注卡/提示）共用一套版式：标题写进挂牌、
-- 资金右对齐在标题行、正文从 490 起自动换行、实心按钮压在卡底 605..657。
local CARD_VISUAL = {
  title = { cx = CARD_PLATE.cx, y = CARD_PLATE.y },
  funds = { right = CARD_FUNDS.right, y = CARD_FUNDS.y, w = CARD_FUNDS.w },
  text = {
    x = CARD_TEXT.x,
    y = CARD_TEXT.y,
    w = CARD_TEXT.w,
    h = CARD_TEXT.maxLines * CARD_TEXT.lineHeight,
    lineHeight = CARD_TEXT.lineHeight,
  },
  button = { x = 170, y = CARD_BTN_Y, w = 140, h = SERVICE_BTN.h, label = "确认" },
}

local modal_visuals = {
  new_game = {
    title = { cx = CARD_PLATE.cx, y = CARD_PLATE.y },
    text = CARD_VISUAL.text,
    icon = { x = 123, y = 552, w = 48, h = 48 },
    cash = { x = 187, y = 566, w = 200, h = 40 },
  },
  quit_game = CARD_VISUAL,
  buy_goods = {
    title = { x = 43, y = 416 },
    icon = { x = 47, y = 444, w = 56, h = 56 },
    goods = { x = 115, y = 452, w = 310, h = 40 },
    input = { x = 196, y = TRADE_QTY_Y, w = 64, h = QTY_BTN.h },
    guidance = { centerX = 240, bottom = 568, w = 395, lineHeight = 22 },
    fieldTextOffsetY = 8,
  },
  sell_goods = {
    title = { x = 43, y = 416 },
    icon = { x = 47, y = 444, w = 56, h = 56 },
    goods = { x = 115, y = 452, w = 310, h = 40 },
    input = { x = 196, y = TRADE_QTY_Y, w = 64, h = QTY_BTN.h },
    guidance = { centerX = 240, bottom = 568, w = 395, lineHeight = 22 },
    fieldTextOffsetY = 8,
  },
  bank = CARD_VISUAL,
  hospital = CARD_VISUAL,
  agency = {
    -- 标题写进卡面左上那块挂牌里，资金跟在同一行右侧。
    title = { cx = 89, y = 449 },
    funds = { right = 456, y = 449, w = 286 },
    prefix = { x = 56, y = 491, w = 48 },
    input = { x = 154, y = AGENCY_STEPPER.y, w = 76, h = AGENCY_STEPPER.h },
    suffix = { x = 280, y = 491, w = 144 },
    note = { centerX = 240, y = 533 },
    fieldTextOffsetY = 10,
  },
  price_note = CARD_VISUAL,
  life_note = CARD_VISUAL,
  sick_blackout = CARD_VISUAL,
  sick_dead = CARD_VISUAL,
  time_up = CARD_VISUAL,
  sell_reputation = CARD_VISUAL,
  no_money = CARD_VISUAL,
  status = CARD_VISUAL,
  buy_succ = {
    image = { x = 67, y = 181, w = 347, h = 289 },
    text = { x = 71, y = 477, w = 337, h = 84, lineHeight = 24 },
  },
}

local function copy_rect(rect)
  if rect == nil then return nil end
  return { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
end

function Layout.overlay_frame(kind)
  return copy_rect(overlay_frames[kind])
end

function Layout.modal_visual(kind)
  local source = modal_visuals[kind]
  if source == nil then return nil end
  local out = {}
  for name, item in pairs(source) do
    if type(item) == "table" then
      out[name] = {}
      for key, value in pairs(item) do out[name][key] = value end
    else
      out[name] = item
    end
  end
  return out
end

local overlay_action_sets = {
  new_game = {
    action("confirm_new_game", 74, SERVICE_BTN_Y, SERVICE_BTN.w, SERVICE_BTN.h, "开始"),
    action("close_overlay", 306, SERVICE_BTN_Y, SERVICE_BTN.w, SERVICE_BTN.h, "取消"),
  },
  quit_game = {
    action("confirm_quit_game", 74, SERVICE_BTN_Y, SERVICE_BTN.w, SERVICE_BTN.h, "结束"),
    action("close_overlay", 306, SERVICE_BTN_Y, SERVICE_BTN.w, SERVICE_BTN.h, "取消"),
  },
  buy_goods = {
    action("confirm_buy", 48, TRADE_BTN_Y, 180, 72, "确定"),
    action("close_overlay", 252, TRADE_BTN_Y, 180, 72, "取消"),
    action("quantity_minus", 132, TRADE_QTY_Y, QTY_BTN.w, QTY_BTN.h, "－"),
    action("quantity_plus", 276, TRADE_QTY_Y, QTY_BTN.w, QTY_BTN.h, "＋"),
  },
  sell_goods = {
    action("confirm_sell", 48, TRADE_BTN_Y, 180, 72, "确定"),
    action("close_overlay", 252, TRADE_BTN_Y, 180, 72, "取消"),
    action("quantity_minus", 132, TRADE_QTY_Y, QTY_BTN.w, QTY_BTN.h, "－"),
    action("quantity_plus", 276, TRADE_QTY_Y, QTY_BTN.w, QTY_BTN.h, "＋"),
  },
  bank = {
    action("deposit_all", 74, SERVICE_BTN_Y, SERVICE_BTN.w, SERVICE_BTN.h, "存钱"),
    action("withdraw_all", 190, SERVICE_BTN_Y, SERVICE_BTN.w, SERVICE_BTN.h, "取钱"),
    action("close_overlay", 306, SERVICE_BTN_Y, SERVICE_BTN.w, SERVICE_BTN.h, "离开"),
  },
  hospital = {
    action("treat", 128, SERVICE_BTN_Y, SERVICE_BTN.w, SERVICE_BTN.h, "看病"),
    action("close_overlay", 252, SERVICE_BTN_Y, SERVICE_BTN.w, SERVICE_BTN.h, "离开"),
  },
  agency = {
    action("expand", 128, AGENCY_BTN_Y, SERVICE_BTN.w, SERVICE_BTN.h, "成交"),
    action("close_overlay", 252, AGENCY_BTN_Y, SERVICE_BTN.w, SERVICE_BTN.h, "离开"),
    action("quantity_minus", 110, AGENCY_STEPPER.y, AGENCY_STEPPER.w, AGENCY_STEPPER.h, "－"),
    action("quantity_plus", 230, AGENCY_STEPPER.y, AGENCY_STEPPER.w, AGENCY_STEPPER.h, "＋"),
  },
}

local passive_cards = {
  price_note = true, life_note = true, sick_blackout = true,
  sick_dead = true, time_up = true, sell_reputation = true,
}

local feedback_actions = {
  no_money = { action("confirm_overlay", 170, CARD_BTN_Y, 140, SERVICE_BTN.h, "确认") },
  status = { action("confirm_overlay", 170, CARD_BTN_Y, 140, SERVICE_BTN.h, "确认") },
  buy_succ = { action("confirm_overlay", 207, 575, 67, 39, "确认") },
}

local SELL_QTY_SPECS = {
  { id = "sell_qty_all", divisor = 1, min = 1 },
  { id = "sell_qty_half", divisor = 2, min = 2 },
  { id = "sell_qty_quarter", divisor = 4, min = 4 },
  { id = "sell_qty_tenth", divisor = 10, min = 11 },
}

local BUY_QTY_SPECS = {
  { id = "buy_qty_all", divisor = 1, min = 1 },
  { id = "buy_qty_half", divisor = 2, min = 2 },
  { id = "buy_qty_quarter", divisor = 4, min = 4 },
  { id = "buy_qty_tenth", divisor = 10, min = 11 },
}

local AGENCY_QTY_SPECS = {
  { id = "agency_qty_all", divisor = 1, min = 1 },
  { id = "agency_qty_half", divisor = 2, min = 2 },
  { id = "agency_qty_quarter", divisor = 4, min = 4 },
  { id = "agency_qty_tenth", divisor = 10, min = 11 },
}

local function quantity_actions(specs, frame, quantity, row_y)
  quantity = math.floor(tonumber(quantity) or 0)
  local visible = {}
  for _, spec in ipairs(specs) do
    if quantity >= spec.min then
      visible[#visible + 1] = spec
    end
  end
  local count = #visible
  -- 只剩「全部」时和加减重复，不再画一条只有数字的底栏。
  if count < 2 then return {} end
  local y = row_y or (frame.y + frame.h - QTY_ROW_HEIGHT)
  local h = QTY_ROW_HEIGHT
  local gap = 8
  local pad = 16
  local base = math.floor((frame.w - pad * 2 - gap * (count - 1)) / count)
  local used = 0
  local out = {}
  for _, spec in ipairs(visible) do
    local word = "全部"
    if string.find(spec.id, "half", 1, true) then word = "一半"
    elseif string.find(spec.id, "quarter", 1, true) then word = "四分"
    elseif string.find(spec.id, "tenth", 1, true) then word = "一成" end
    out[#out + 1] = action(spec.id, frame.x + pad + used, y, base, h, word)
    used = used + base + gap
  end
  return out
end

function Layout.sell_qty_actions(stock)
  return quantity_actions(SELL_QTY_SPECS, overlay_frames.sell_goods, stock, TRADE_SHORTCUT_Y)
end

function Layout.buy_qty_actions(maximum)
  return quantity_actions(BUY_QTY_SPECS, overlay_frames.buy_goods, maximum, TRADE_SHORTCUT_Y)
end

function Layout.agency_maximum(saved)
  local game = saved and saved.game
  if not game then return 1 end
  local funds = (tonumber(game.cash) or 0) + (tonumber(game.deposit) or 0)
  return math.max(1, math.floor(funds / 10000))
end

function Layout.agency_qty_actions(maximum)
  -- 快捷数量条只在买得起 2 套以上时才出现，免得和「全部」这种单按钮重复。
  local visible = {}
  for _, spec in ipairs(AGENCY_QTY_SPECS) do
    if (tonumber(maximum) or 1) >= spec.min then visible[#visible + 1] = spec end
  end
  if #visible < 2 then return {} end
  local total = #visible * AGENCY_CHIP.w + (#visible - 1) * AGENCY_CHIP.gap
  local x = math.floor((AGENCY_FRAME.w - total) / 2)
  local out = {}
  for _, spec in ipairs(visible) do
    local word = "全部"
    if spec.divisor == 2 then word = "一半"
    elseif spec.divisor == 4 then word = "四分"
    elseif spec.divisor == 10 then word = "一成" end
    out[#out + 1] = action(spec.id, x, AGENCY_CHIP.y, AGENCY_CHIP.w, AGENCY_CHIP.h, word)
    x = x + AGENCY_CHIP.w + AGENCY_CHIP.gap
  end
  return out
end

local function sell_stock(saved)
  local overlay = saved and saved.overlay
  local game = saved and saved.game
  if not overlay or not game or overlay.kind ~= "sell_goods" then return 0 end
  local item = game.inventory and game.inventory[overlay.index]
  return item and item.quantity or 0
end

local function buy_maximum(saved)
  local overlay = saved and saved.overlay
  local game = saved and saved.game
  if not overlay or not game or overlay.kind ~= "buy_goods" then return 0 end
  local offer = game.market and game.market[overlay.index]
  if not offer or not offer.price or offer.price <= 0 then return 0 end
  local inventory = game.inventory or {}
  local has_goods = false
  for _, item in ipairs(inventory) do
    if item and item.goods_id == offer.goods_id then
      has_goods = true
      break
    end
  end
  if #inventory >= 5 and not has_goods then return 0 end
  local by_funds = math.floor(((game.cash or 0) + (game.deposit or 0)) / offer.price)
  local by_capacity = math.max(0, (game.capacity or 0) - (game.used or 0))
  return math.max(0, math.min(by_funds, by_capacity))
end

function Layout.buy_maximum(saved)
  return buy_maximum(saved)
end

function Layout.overlay_actions(saved)
  local overlay = saved.overlay
  if type(overlay) ~= "table" or type(overlay.kind) ~= "string" then return {} end
  local source = overlay_action_sets[overlay.kind]
  if source then
    local out = copy_actions(source)
    if overlay.kind == "hospital" then
      local game = saved.game
      if game and game.health >= 100 then
        return { out[2] }
      end
      local cost = game and (100 - game.health) * 5000 or 0
      local disabled = game == nil or game.status ~= "playing"
        or game.cash + game.deposit < cost
      out[1].disabled = disabled and true or nil
    elseif overlay.kind == "buy_goods" then
      for _, item in ipairs(Layout.buy_qty_actions(buy_maximum(saved))) do
        out[#out + 1] = item
      end
    elseif overlay.kind == "sell_goods" then
      for _, item in ipairs(Layout.sell_qty_actions(sell_stock(saved))) do
        out[#out + 1] = item
      end
    elseif overlay.kind == "agency" then
      for _, item in ipairs(Layout.agency_qty_actions(Layout.agency_maximum(saved))) do
        out[#out + 1] = item
      end
    end
    return out
  end
  source = feedback_actions[overlay.kind]
  if source then return copy_actions(source) end
  if passive_cards[overlay.kind] then
    local frame = overlay_frames[overlay.kind]
    return {
      action("confirm_overlay", frame.x, frame.y, frame.w, frame.h, "确认"),
    }
  end
  return {}
end

function Layout.hit(item, x, y)
  return x >= item.x and x < item.x + item.w
    and y >= item.y and y < item.y + item.h
end

-- 绘制模块读不到本文件的 local，买卖卡片的坐标从这里带过去。
Layout.trade_metrics = {
  qty_y = TRADE_QTY_Y,
  shortcut_y = TRADE_SHORTCUT_Y,
  qty_h = QTY_BTN.h,
  hint_y = 304,
}

return Layout

end
__bundle["ui.runtime"] = function()
local Economy = require("domain.economy")
local Events = require("domain.events")
local Houses = require("domain.houses")
local Layout = require("ui.layout")
local Random = require("domain.random")
local Save = require("domain.save")
local State = require("domain.game_state")
local View = require("ui.view")

local Runtime = {}
local office = nil

local SCREENS = {
  main = true, story = true, houses = true, records = true, help = true,
}

local OVERLAY_KINDS = {
  new_game = true, quit_game = true,
  buy_goods = true, sell_goods = true,
  bank = true, hospital = true, agency = true,
  price_note = true, life_note = true,
  sick_blackout = true, sick_dead = true, time_up = true,
  sell_reputation = true, no_money = true,
  status = true, buy_succ = true,
}

local PASSIVE_OVERLAY_KINDS = {
  price_note = true, life_note = true,
  sick_blackout = true, sick_dead = true, time_up = true,
  sell_reputation = true, no_money = true,
  status = true, buy_succ = true,
}

local REASONS = {
  insufficient_funds = "资金不足",
  capacity_limit = "仓容不足",
  slot_limit = "库存品类已满",
  not_in_market = "本周无此行情",
  insufficient_quantity = "库存不足",
  health_full = "健康已满",
  reputation_rejected = "名声资格未通过",
  invalid_office = "售楼资格已失效",
  invalid_market_index = "无效商品",
  invalid_inventory_index = "无效库存",
}


local HOUSE_SUCCESS_MESSAGES = {
  "    一年摆摊下来， 我终于有了自己的临街单间， 虽小， 但收摊后能关上门。",
  "    一年没白熬， 巷口老屋的钥匙到手， 夜市散了我也有地方落脚。",
  "    靠着这一年的进出货， 我买下灯市小楼， 不用再和人合租阁楼。",
  "    没日没夜地盯行情， 复式阁楼成了我的， 摊位和住处终于分开了。",
  "    一年把货做起来， 连排小院到手， 连父母来帮摊也住得下。",
  "    从地摊到江岸雅居， 我把自己从摊主做成了这城夜市里的人物。",
  "    白手进货， 一年买下城芯府邸， 灯市的年轻人开始拿我当例子。",
  "    从借铺到林间别院， 只花了一年。 别人觉得玄， 我只觉得账本没骗我。",
  "    海岛木屋的钥匙在口袋里发烫。 钱对我来说像夜里的灯， 多到可以一直亮着。",
  "    货做大了， 我把目光放到更远的地方， 星港居所是下一站。 再见， 这座夜市。",
}

local function base_saved()
  return {
    schema = 2,
    screen = "story",
    overlay = nil,
    focus = 1,
    overlay_focus = 1,
    quantity = 1,
    current_market = 1,
    story_seen = false,
    story_step = 1,
    help_step = 1,
    house_scroll = 1,
    game = nil,
    records = Save.default_records(),
    message_queue = {},
    seed_counter = 0,
  }
end

local function finite_integer(value)
  return type(value) == "number"
    and value == value
    and value ~= math.huge
    and value ~= -math.huge
    and value == math.floor(value)
end

local function array_length(value)
  if type(value) ~= "table" then return nil end
  local count, maximum = 0, 0
  for key in pairs(value) do
    if not finite_integer(key) or key < 1 then return nil end
    count = count + 1
    maximum = math.max(maximum, key)
  end
  if count ~= maximum then return nil end
  for index = 1, maximum do
    if rawget(value, index) == nil then return nil end
  end
  return maximum
end

local function valid_rng(rng)
  if type(rng) ~= "table"
      or not finite_integer(rng.state)
      or rng.state <= 0
      or not finite_integer(rng.forced_index) then
    return false
  end
  local count = array_length(rng.forced_rolls)
  if count == nil or rng.forced_index < 1 or rng.forced_index > count + 1 then
    return false
  end
  for index = 1, count do
    local roll = rng.forced_rolls[index]
    if type(roll) ~= "number" or roll ~= roll or roll < 0 or roll >= 1
        or roll == math.huge or roll == -math.huge then
      return false
    end
  end
  return true
end

local function valid_game(game)
  if type(game) ~= "table" then return false end
  for _, field in ipairs({
    "week", "week_limit", "cash", "deposit", "health", "reputation",
    "capacity", "used", "selected_house",
  }) do
    if not finite_integer(game[field]) then return false end
  end
  if game.week < 1 or game.week > 53 or game.week_limit ~= 52
      or game.cash < 0 or game.deposit < 0
      or game.health < 0 or game.health > 100
      or game.reputation < 0 or game.reputation > 100
      or game.capacity < 1 or game.used < 0 or game.used > game.capacity
      or game.selected_house < 1 or game.selected_house > 10
      or (game.status ~= "playing" and game.status ~= "won" and game.status ~= "lost")
      or (game.ending ~= nil and type(game.ending) ~= "string")
      or not valid_rng(game.rng) then
    return false
  end

  local market_count = array_length(game.market)
  local inventory_count = array_length(game.inventory)
  local house_count = array_length(game.house_prices)
  if market_count ~= 5 or inventory_count == nil or inventory_count > 5 or house_count ~= 10 then
    return false
  end
  local seen_market = {}
  for index = 1, market_count do
    local offer = game.market[index]
    if type(offer) ~= "table"
        or not finite_integer(offer.goods_id) or offer.goods_id < 1 or offer.goods_id > 8
        or not finite_integer(offer.price) or offer.price <= 0
        or seen_market[offer.goods_id] then
      return false
    end
    seen_market[offer.goods_id] = true
  end
  local inventory_total = 0
  local seen_inventory = {}
  for index = 1, inventory_count do
    local item = game.inventory[index]
    if type(item) ~= "table"
        or not finite_integer(item.goods_id) or item.goods_id < 1 or item.goods_id > 8
        or not finite_integer(item.quantity) or item.quantity <= 0
        or not finite_integer(item.average_cost) or item.average_cost <= 0
        or seen_inventory[item.goods_id] then
      return false
    end
    seen_inventory[item.goods_id] = true
    inventory_total = inventory_total + item.quantity
  end
  if inventory_total ~= game.used then return false end
  for index = 1, house_count do
    if not finite_integer(game.house_prices[index]) or game.house_prices[index] <= 0 then
      return false
    end
  end
  return true
end

local function snap_near_int(value)
  if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
    return value
  end
  if value == math.floor(value) then
    return value
  end
  local snapped = value >= 0 and math.floor(value + 0.5) or -math.floor(-value + 0.5)
  if math.abs(value - snapped) <= 1e-6 then
    return snapped
  end
  return value
end

local function floor_price(value)
  value = snap_near_int(value)
  if type(value) == "number" and value < 1 then
    return 1
  end
  return value
end

local function clamp_stat(value)
  value = snap_near_int(value)
  if type(value) == "number" then
    if value < 0 then return 0 end
    if value > 100 then return 100 end
  end
  return value
end

local function sanitize_game(game)
  if type(game) ~= "table" then return end
  if type(game.rng) == "table" then
    Random.sanitize(game.rng)
  end
  for _, field in ipairs({
    "week", "week_limit", "cash", "deposit", "capacity", "used", "selected_house",
  }) do
    game[field] = snap_near_int(game[field])
  end
  game.health = clamp_stat(game.health)
  game.reputation = clamp_stat(game.reputation)
  if type(game.market) == "table" then
    for index = 1, 5 do
      local offer = game.market[index]
      if type(offer) == "table" then
        offer.goods_id = snap_near_int(offer.goods_id)
        offer.price = floor_price(offer.price)
      end
    end
  end
  if type(game.house_prices) == "table" then
    for index, price in ipairs(game.house_prices) do
      game.house_prices[index] = floor_price(price)
    end
  end
  if type(game.inventory) == "table" then
    for _, item in ipairs(game.inventory) do
      if type(item) == "table" then
        item.goods_id = snap_near_int(item.goods_id)
        item.quantity = snap_near_int(item.quantity)
        item.average_cost = snap_near_int(item.average_cost)
      end
    end
  end
end

local function copy_overlay(value)
  if type(value) ~= "table" or type(value.kind) ~= "string"
      or not OVERLAY_KINDS[value.kind] then
    return nil
  end
  local copy = { kind = value.kind }
  if value.index ~= nil then
    if not finite_integer(value.index) or value.index < 1 or value.index > 5 then return nil end
    copy.index = value.index
  end
  if value.title ~= nil then
    if type(value.title) ~= "string" then return nil end
    copy.title = value.title
  end
  if value.text ~= nil then
    if type(value.text) ~= "string" then return nil end
    copy.text = value.text
  end
  if value.page ~= nil then
    if not finite_integer(value.page) or value.page < 1 then return nil end
    copy.page = value.page
  end
  if (copy.kind == "buy_goods" or copy.kind == "sell_goods") and copy.index == nil then
    return nil
  end
  return copy
end

local function copy_passive_overlay(value)
  local copy = copy_overlay(value)
  if copy == nil or not PASSIVE_OVERLAY_KINDS[copy.kind]
      or type(copy.title) ~= "string" or type(copy.text) ~= "string" then
    return nil
  end
  return copy
end

local function overlays_equal(left, right)
  return left ~= nil and right ~= nil
    and left.kind == right.kind
    and left.index == right.index
    and left.title == right.title
    and left.text == right.text
    and left.page == right.page
end

local function normalize_message_queue(value)
  local count = array_length(value)
  if count == nil then return {}, false end
  local out = {}
  for index = 1, count do
    local item = copy_passive_overlay(value[index])
    if item == nil then return {}, false end
    out[index] = item
  end
  return out, true
end

local function legacy_message(message, game)
  if type(message) ~= "table"
      or type(message.kind) ~= "string"
      or type(message.title) ~= "string"
      or type(message.text) ~= "string" then
    return nil
  end
  local kinds = {
    price = "price_note",
    life = "life_note",
    sickness = game and game.ending == "dead" and "sick_dead" or "sick_blackout",
    status = "status",
  }
  return {
    kind = kinds[message.kind] or "status",
    title = message.title,
    text = message.text,
  }
end

local function open_overlay(saved, overlay)
  saved.overlay = overlay
  saved.overlay_focus = 1
end

local function show_queue_head(saved)
  local head = saved.message_queue[1]
  if head then
    open_overlay(saved, copy_passive_overlay(head))
  else
    saved.overlay = nil
    saved.overlay_focus = 1
  end
end

local function advance_queue(saved)
  table.remove(saved.message_queue, 1)
  show_queue_head(saved)
end

local function set_passive_overlay(saved, overlay)
  saved.message_queue = { overlay }
  show_queue_head(saved)
end

local function migrate_schema_one(saved)
  local legacy_screen = saved.screen
  local legacy_messages = saved.message_queue
  saved.schema = 2
  saved.screen = (legacy_screen == "houses" or legacy_screen == "records")
    and legacy_screen or "main"
  saved.focus = 1
  saved.overlay = nil
  saved.overlay_focus = 1
  saved.message_queue = {}
  saved.story_seen = true
  saved.story_step = 5
  saved.help_step = 1
  saved.house_scroll = math.max(1, math.min(9,
    saved.game and saved.game.selected_house or 1
  ))

  if legacy_screen == "dialog" then
    local count = array_length(legacy_messages)
    if count then
      for index = 1, count do
        local item = legacy_message(legacy_messages[index], saved.game)
        if item then saved.message_queue[#saved.message_queue + 1] = item end
      end
    end
    show_queue_head(saved)
  elseif saved.game and saved.game.status == "playing" then
    if legacy_screen == "bank" or legacy_screen == "hospital" or legacy_screen == "agency" then
      open_overlay(saved, { kind = legacy_screen })
    end
  elseif legacy_screen == "result" and saved.game then
    if saved.game.status == "won" then
      set_passive_overlay(saved, {
        kind = "buy_succ",
        title = "购房成功",
        text = HOUSE_SUCCESS_MESSAGES[saved.game.selected_house] or "本局已完成置业",
        page = 1,
      })
    else
      set_passive_overlay(saved, {
        kind = saved.game.ending == "time_up" and "time_up" or "sick_dead",
        title = "本局结束",
        text = saved.game.ending == "time_up"
          and "    我的豪情壮志最终没有成为现实， 一年时间过去了， 我没能买到属于自己的房子。 回到冰冷的出租屋， 我收拾东西打算回老家去了。"
          or Events.death_text(),
      })
    end
  end
  saved.return_screen = nil
end

local function first_enabled_from(actions, start)
  if #actions == 0 then return nil end
  for offset = 0, #actions - 1 do
    local index = (start + offset - 1) % #actions + 1
    if not actions[index].disabled then return index end
  end
  return nil
end

local function next_enabled(actions, start, delta)
  if #actions == 0 then return nil end
  for offset = 1, #actions do
    local index = (start - 1 + delta * offset) % #actions + 1
    if not actions[index].disabled then return index end
  end
  return nil
end

local function move_focus_in_row(actions, start, delta)
  local current = actions[start]
  if not current then return nil end
  local row = {}
  for index, item in ipairs(actions) do
    if not item.disabled and math.abs((item.y or 0) - (current.y or 0)) <= 8 then
      row[#row + 1] = index
    end
  end
  table.sort(row, function(a, b) return actions[a].x < actions[b].x end)
  local place = 1
  for i, index in ipairs(row) do
    if index == start then
      place = i
      break
    end
  end
  local next_place = place + delta
  if next_place < 1 or next_place > #row then return nil end
  return row[next_place]
end

local function clamp_focus(saved)
  local actions = Layout.actions(saved)
  local focus = #actions == 0 and nil
    or math.max(1, math.min(#actions, saved.focus or 1))
  saved.focus = focus and first_enabled_from(actions, focus) or 1

  local overlays = Layout.overlay_actions(saved)
  local overlay_focus = #overlays == 0 and nil
    or math.max(1, math.min(#overlays, saved.overlay_focus or 1))
  saved.overlay_focus = overlay_focus and first_enabled_from(overlays, overlay_focus) or 1
end

local function normalize_overlay_queue(saved)
  local passive_overlay = copy_passive_overlay(saved.overlay)
  if #saved.message_queue > 0 then
    if passive_overlay and overlays_equal(passive_overlay, saved.message_queue[1]) then
      saved.overlay = passive_overlay
    else
      saved.message_queue = {}
      if passive_overlay then saved.overlay = nil end
    end
  elseif passive_overlay then
    saved.overlay = nil
  end
end

local function normalize_saved(ctx)
  local saved = ctx.state.maifangji
  if type(saved) ~= "table" then
    saved = base_saved()
    ctx.state.maifangji = saved
  end

  local source_schema = saved.schema
  saved.focus = finite_integer(saved.focus) and math.max(1, saved.focus) or 1
  saved.overlay_focus = finite_integer(saved.overlay_focus)
    and math.max(1, saved.overlay_focus) or 1
  saved.quantity = finite_integer(saved.quantity)
    and math.max(1, math.min(999, saved.quantity)) or 1
  saved.current_market = finite_integer(saved.current_market)
    and math.max(1, math.min(3, saved.current_market)) or 1
  saved.story_seen = type(saved.story_seen) == "boolean" and saved.story_seen or false
  saved.story_step = finite_integer(saved.story_step)
    and math.max(1, math.min(5, saved.story_step)) or 1
  saved.help_step = finite_integer(saved.help_step)
    and math.max(1, math.min(9, saved.help_step)) or 1
  saved.house_scroll = finite_integer(saved.house_scroll)
    and math.max(1, math.min(9, saved.house_scroll)) or 1
  saved.seed_counter = finite_integer(saved.seed_counter)
    and math.max(0, saved.seed_counter) or 0
  saved.records = Save.decode(saved.records)

  if saved.game ~= nil then
    sanitize_game(saved.game)
    if not valid_game(saved.game) then saved.game = nil end
  end
  if source_schema == 1 then
    migrate_schema_one(saved)
  elseif source_schema ~= 2 and saved.game == nil then
    local records = saved.records
    saved = base_saved()
    saved.records = records
    ctx.state.maifangji = saved
  else
    saved.schema = 2
    if not SCREENS[saved.screen] then saved.screen = "main" end
    saved.overlay = copy_overlay(saved.overlay)
    local source_messages = saved.message_queue
    local temporary_queue = source_messages == nil and saved.queue ~= nil
    if temporary_queue then source_messages = saved.queue end
    local messages, messages_valid = normalize_message_queue(source_messages)
    saved.message_queue = messages
    if temporary_queue and messages_valid then
      local passive_overlay = copy_passive_overlay(saved.overlay)
      if passive_overlay and not overlays_equal(passive_overlay, saved.message_queue[1]) then
        table.insert(saved.message_queue, 1, passive_overlay)
      end
    end
  end
  saved.queue = nil

  if saved.game == nil then
    if saved.screen == "houses" then saved.screen = "main" end
    if saved.overlay and saved.overlay.kind ~= "new_game"
        and saved.overlay.kind ~= "status" and saved.overlay.kind ~= "no_money" then
      saved.overlay = nil
    end
    saved.message_queue = {}
  elseif saved.game.status ~= "playing" then
    if saved.screen == "houses" then saved.screen = "main" end
    if saved.overlay and (saved.overlay.kind == "buy_goods"
        or saved.overlay.kind == "sell_goods"
        or saved.overlay.kind == "bank"
        or saved.overlay.kind == "hospital"
        or saved.overlay.kind == "agency"
        or saved.overlay.kind == "quit_game") then
      saved.overlay = nil
    end
  end
  normalize_overlay_queue(saved)
  saved.return_screen = nil
  clamp_focus(saved)
  return saved
end

local function close_overlay(saved)
  saved.overlay = nil
  saved.overlay_focus = 1
end

local function feedback(saved, reason)
  local kind = reason == "insufficient_funds" and "no_money" or "status"
  set_passive_overlay(saved, {
    kind = kind,
    title = kind == "no_money" and "钱不够" or "提示",
    text = REASONS[reason] or tostring(reason),
  })
end

local function new_game(saved)
  saved.seed_counter = saved.seed_counter + 1
  saved.game = State.new(20260903 + saved.seed_counter)
  saved.screen = "main"
  saved.quantity = 1
  saved.current_market = 1
  saved.message_queue = {}
  saved.overlay = nil
  saved.overlay_focus = 1
  saved.focus = 1
  office = nil
end

local function open_houses(saved)
  if not saved.game or saved.game.status ~= "playing" then return false end
  office = Houses.open_office(saved.game, saved.game.rng)
  saved.screen = "houses"
  saved.house_scroll = math.max(1, math.min(9, saved.game.selected_house))
  saved.focus = 1
  return true
end

local function queue_week_events(saved, market_id)
  local game = saved.game
  if not game or game.status ~= "playing" or market_id == saved.current_market then return false end
  saved.current_market = market_id
  local advanced = Economy.advance_week(game)
  if not advanced.ok then
    set_passive_overlay(saved, {
      kind = "time_up",
      title = "本局结束",
      text = "    我的豪情壮志最终没有成为现实， 一年时间过去了， 我没能买到属于自己的房子。 回到冰冷的出租屋， 我收拾东西打算回老家去了。",
    })
    return true
  end

  local messages = {}
  local price = Events.price_event(game, game.rng)
  messages[#messages + 1] = {
    kind = "price_note",
    title = "行情快报",
    text = Events.price_text(price),
  }
  local life = Events.life_event(game, game.rng)
  if life.id ~= "none" then
    messages[#messages + 1] = {
      kind = "life_note",
      title = "人生插曲",
      text = Events.life_text(life.id) or life.id,
    }
  end
  local sickness = Events.sickness(game, game.rng)
  if sickness == "blackout" then
    local aid = Events.apply_blackout_aid(game)
    messages[#messages + 1] = {
      kind = "sick_blackout",
      title = "突发昏倒",
      text = Events.blackout_text(aid),
    }
  elseif sickness == "dead" then
    game.status = "lost"
    game.ending = "dead"
    messages[#messages + 1] = {
      kind = "sick_dead", title = "健康警报", text = Events.death_text(),
    }
  end
  saved.message_queue = messages
  show_queue_head(saved)
  return true
end

local function timestamp(ctx, game)
  local now = ctx.clock:now()
  local value = now.local_sec
  if value == nil then value = now.epoch_sec end
  if value == nil then return "第" .. tostring(game.week) .. "周" end
  return tostring(value)
end

local function run_main_action(saved, id)
  local game = saved.game
  if id == "start_game" then
    open_overlay(saved, {
      kind = game and game.status == "playing" and "quit_game" or "new_game",
    })
    return true
  elseif id == "records" or id == "help" then
    saved.screen = id
    saved.focus = 1
    if id == "help" then saved.help_step = 1 end
    return true
  elseif id == "houses" then
    return open_houses(saved)
  elseif id == "bank" or id == "hospital" or id == "agency" then
    if not game or game.status ~= "playing" then return false end
    open_overlay(saved, { kind = id })
    return true
  end

  local market_id = tonumber(string.match(id, "^market(%d+)$"))
  if market_id then return queue_week_events(saved, market_id) end

  local buy_index = tonumber(string.match(id, "^buy_(%d+)$"))
  if buy_index and game and game.status == "playing" and game.market[buy_index] then
    saved.quantity = 1
    open_overlay(saved, { kind = "buy_goods", index = buy_index })
    return true
  end
  local sell_index = tonumber(string.match(id, "^sell_(%d+)$"))
  if sell_index and game and game.status == "playing" and game.inventory[sell_index] then
    saved.quantity = 1
    open_overlay(saved, { kind = "sell_goods", index = sell_index })
    return true
  end
  return false
end

local function run_overlay_action(saved, id)
  local game = saved.game
  local overlay = saved.overlay
  if not overlay then return false end
  if id == "close_overlay" then
    close_overlay(saved)
  elseif id == "confirm_overlay" then
    if overlay.kind == "buy_succ" then
      local pages = View.success_text_pages(overlay.text)
      local page = overlay.page or 1
      if page < #pages then
        overlay.page = page + 1
        if saved.message_queue[1] then
          saved.message_queue[1].page = overlay.page
        end
        return true
      end
    end
    if #saved.message_queue > 0 then advance_queue(saved) else close_overlay(saved) end
  elseif id == "confirm_new_game" then
    new_game(saved)
  elseif id == "confirm_quit_game" then
    if not game or game.status ~= "playing" then return false end
    game.status = "lost"
    game.ending = "quit"
    close_overlay(saved)
  elseif id == "quantity_minus" then
    saved.quantity = math.max(1, saved.quantity - 1)
  elseif id == "quantity_plus" then
    if overlay.kind == "sell_goods" then
      local item = game and game.inventory[overlay.index]
      local stock = item and item.quantity or 0
      if saved.quantity >= stock then
        feedback(saved, "insufficient_quantity")
        return true
      end
      saved.quantity = math.min(stock, saved.quantity + 1)
    else
      saved.quantity = math.min(999, saved.quantity + 1)
    end
  elseif id == "sell_qty_all" or id == "sell_qty_half"
      or id == "sell_qty_quarter" or id == "sell_qty_tenth" then
    if overlay.kind ~= "sell_goods" or not game then return false end
    local item = game.inventory[overlay.index]
    local stock = item and item.quantity or 0
    local divisor = id == "sell_qty_all" and 1
      or id == "sell_qty_half" and 2
      or id == "sell_qty_quarter" and 4
      or 10
    saved.quantity = math.max(1, math.floor(stock / divisor))
  elseif id == "buy_qty_all" or id == "buy_qty_half"
      or id == "buy_qty_quarter" or id == "buy_qty_tenth" then
    if overlay.kind ~= "buy_goods" or not game then return false end
    local maximum = Layout.buy_maximum(saved)
    if maximum < 1 then return false end
    local divisor = id == "buy_qty_all" and 1
      or id == "buy_qty_half" and 2
      or id == "buy_qty_quarter" and 4
      or 10
    saved.quantity = math.max(1, math.floor(maximum / divisor))
  elseif id == "agency_qty_all" or id == "agency_qty_half"
      or id == "agency_qty_quarter" or id == "agency_qty_tenth" then
    if overlay.kind ~= "agency" or not game then return false end
    local maximum = Layout.agency_maximum(saved)
    local divisor = id == "agency_qty_all" and 1
      or id == "agency_qty_half" and 2
      or id == "agency_qty_quarter" and 4
      or 10
    saved.quantity = math.max(1, math.floor(maximum / divisor))
  elseif id == "confirm_buy" then
    if overlay.kind ~= "buy_goods" or not game then return false end
    local result = Economy.buy(game, overlay.index, saved.quantity)
    if result.ok then close_overlay(saved) else feedback(saved, result.reason) end
  elseif id == "confirm_sell" then
    if overlay.kind ~= "sell_goods" or not game then return false end
    local item = game.inventory[overlay.index]
    local goods_id = item and item.goods_id
    local result = Economy.sell(game, overlay.index, saved.quantity)
    if result.ok and (goods_id == 3 or goods_id == 7) then
      set_passive_overlay(saved, {
        kind = "sell_reputation",
        title = "名声变化",
        text = "倒卖微商面膜和X4 Pro会掉名声。 砖家说：年轻人要洁身自好。",
      })
    elseif result.ok then
      close_overlay(saved)
    else
      feedback(saved, result.reason)
    end
  elseif id == "deposit_all" then
    if not game then return false end
    Economy.deposit_all(game)
    close_overlay(saved)
  elseif id == "withdraw_all" then
    if not game then return false end
    Economy.withdraw_all(game)
    close_overlay(saved)
  elseif id == "treat" then
    if not game then return false end
    local result = Economy.treat(game)
    if not result.ok then feedback(saved, result.reason) end
  elseif id == "expand" then
    if not game then return false end
    local result = Economy.expand_capacity(game, saved.quantity)
    if result.ok then close_overlay(saved) else feedback(saved, result.reason) end
  else
    return false
  end
  return true
end

local move_house_page

local function run_screen_action(ctx, saved, id)
  local game = saved.game
  if id == "return_main" then
    office = nil
    saved.screen = "main"
    saved.focus = 1
  elseif id == "continue_story" and saved.screen == "story" then
    saved.story_step = math.min(5, saved.story_step + 1)
  elseif id == "finish_story" and saved.screen == "story"
      and saved.story_step >= 5 then
    saved.story_seen = true
    saved.story_step = 5
    saved.screen = "main"
    saved.focus = 1
  elseif id == "help_next" and saved.screen == "help" and saved.help_step < 9 then
    saved.help_step = saved.help_step + 1
  elseif id == "house_prev" and saved.screen == "houses" then
    return move_house_page(saved, -1)
  elseif id == "house_next" and saved.screen == "houses" then
    return move_house_page(saved, 1)
  elseif id == "house_buy" and game then
    local result = Houses.buy(game, game.selected_house, timestamp(ctx, game), office)
    if result.ok then
      Save.record_success(saved.records, game.selected_house, result.purchased_at)
      office = nil
      saved.screen = "main"
      set_passive_overlay(saved, {
        kind = "buy_succ",
        title = "购房成功",
        text = HOUSE_SUCCESS_MESSAGES[game.selected_house] or "本局已完成置业",
        page = 1,
      })
    else
      feedback(saved, result.reason)
    end
  else
    return false
  end
  return true
end

local function back(saved)
  if saved.overlay then
    if #saved.message_queue > 0
        and overlays_equal(saved.overlay, saved.message_queue[1]) then
      advance_queue(saved)
    else
      close_overlay(saved)
      saved.message_queue = {}
    end
    return true
  end
  if saved.screen == "houses" or saved.screen == "records"
      or saved.screen == "help" or saved.screen == "story" then
    office = nil
    saved.screen = "main"
    saved.focus = 1
    return true
  end
  return false
end

local function active_actions(saved)
  if saved.overlay then
    return Layout.overlay_actions(saved), "overlay_focus"
  end
  return Layout.actions(saved), "focus"
end

function move_house_page(saved, delta)
  local game = saved.game
  if not game then return false end
  local start = Layout.house_page_start(saved) + delta * 2
  if start < 1 or start > 9 then return false end
  saved.house_scroll = start
  game.selected_house = start
  return true
end

local function key_input(ctx, saved, ev)
  if ev.key == "back" then
    if ev.phase ~= "up" then return true end
    return back(saved)
  end
  if ev.phase ~= "down" then return false end
  if saved.overlay == nil and saved.screen == "houses" then
    if ev.key == "up" then return move_house_page(saved, -1) end
    if ev.key == "down" then return move_house_page(saved, 1) end
  end
  local actions, focus_field = active_actions(saved)
  if ev.key == "up" then
    local next_focus = next_enabled(actions, saved[focus_field], -1)
    if not next_focus then return false end
    saved[focus_field] = next_focus
  elseif ev.key == "down" then
    local next_focus = next_enabled(actions, saved[focus_field], 1)
    if not next_focus then return false end
    saved[focus_field] = next_focus
  elseif ev.key == "left" or ev.key == "right" then
    local delta = ev.key == "left" and -1 or 1
    if saved.overlay and (saved.overlay.kind == "buy_goods"
        or saved.overlay.kind == "sell_goods" or saved.overlay.kind == "agency") then
      if saved.overlay.kind == "sell_goods" and delta > 0 then
        local item = saved.game and saved.game.inventory[saved.overlay.index]
        local stock = item and item.quantity or 0
        if saved.quantity >= stock then
          feedback(saved, "insufficient_quantity")
        else
          saved.quantity = math.min(stock, saved.quantity + delta)
        end
      else
        saved.quantity = math.max(1, math.min(999, saved.quantity + delta))
      end
    elseif saved.overlay == nil and saved.screen == "main" then
      local moved = move_focus_in_row(actions, saved.focus, delta)
      if not moved then return false end
      saved.focus = moved
    elseif saved.overlay == nil and saved.screen == "houses" then
      local next_focus = next_enabled(actions, saved.focus, delta)
      if not next_focus then return false end
      saved.focus = next_focus
    else
      return false
    end
  elseif ev.key == "ok" then
    local selected = actions[saved[focus_field]]
    if not selected or selected.disabled then return false end
    local handled
    if saved.overlay then
      handled = run_overlay_action(saved, selected.id)
    elseif saved.screen == "main" then
      handled = run_main_action(saved, selected.id)
    else
      handled = run_screen_action(ctx, saved, selected.id)
    end
    if not handled then return false end
  else
    return false
  end
  clamp_focus(saved)
  return true
end

local function touch_input(ctx, saved, ev)
  if saved.overlay == nil and saved.screen == "houses"
      and (ev.gesture == "swipe_up" or ev.gesture == "swipe_down") then
    local viewport = Layout.ACTIVITIES.houses.viewport
    if not Layout.hit(viewport, ev.x, ev.y) then return false end
    return move_house_page(saved, ev.gesture == "swipe_up" and 1 or -1)
  end
  if ev.gesture ~= "tap" then return false end
  if saved.overlay == nil and saved.screen == "houses" then
    for _, row in ipairs(Layout.house_rows(saved)) do
      if Layout.hit(row, ev.x, ev.y) then
        saved.game.selected_house = row.house_index
        return true
      end
    end
  end
  local function activate(actions, focus_field)
    local action_screen = saved.screen
    for index, item in ipairs(actions) do
      if Layout.hit(item, ev.x, ev.y) then
        if item.disabled then return false end
        local handled
        if saved.overlay then
          handled = run_overlay_action(saved, item.id)
        elseif saved.screen == "main" then
          handled = run_main_action(saved, item.id)
        else
          handled = run_screen_action(ctx, saved, item.id)
        end
        if not handled then return false end
        if saved.screen == action_screen then saved[focus_field] = index end
        clamp_focus(saved)
        return true
      end
    end
    return false
  end

  local actions, focus_field = active_actions(saved)
  if activate(actions, focus_field) then return true end
  -- 真机每次触摸会先注入 Click/OK。若焦点停在「结束游戏」，会先弹出认输框，
  -- 手指实际点到的市场就被挡掉；点在框外时取消认输并落到主界面目标。
  if saved.overlay and (saved.overlay.kind == "quit_game" or saved.overlay.kind == "new_game") then
    close_overlay(saved)
    actions, focus_field = active_actions(saved)
    return activate(actions, focus_field)
  end
  return false
end

local function full_screen(screen)
  return screen == "houses" or screen == "records"
    or screen == "help" or screen == "story"
end

local function refresh_mode(before_screen, after_screen, before_house_scroll, after_house_scroll)
  if before_screen ~= after_screen
      and (full_screen(before_screen) or full_screen(after_screen)) then
    return "full"
  end
  if before_screen == "houses" and after_screen == "houses"
      and before_house_scroll ~= after_house_scroll then
    return "full"
  end
  return "partial"
end

function Runtime.boot(ctx)
  local saved = normalize_saved(ctx)
  office = nil
  if not saved.story_seen and saved.game == nil and saved.screen == "main" then
    saved.screen = "story"
    saved.story_step = math.max(1, math.min(5, saved.story_step))
    saved.focus = 1
  end
  if saved.screen == "houses" and saved.game and saved.game.status == "playing" then
    office = Houses.open_office(saved.game, saved.game.rng)
  end
  clamp_focus(saved)
end

function Runtime.state(ctx)
  return normalize_saved(ctx)
end

function Runtime.input(ctx, ev)
  local saved = normalize_saved(ctx)
  local before_screen = saved.screen
  local before_house_scroll = saved.house_scroll
  local handled
  if ev.type == "key" then
    handled = key_input(ctx, saved, ev)
  elseif ev.type == "pointer" then
    if ev.phase ~= "up" then return false end
    handled = touch_input(ctx, saved, ev)
  else
    return false
  end
  if handled then
    if refresh_mode(
      before_screen,
      saved.screen,
      before_house_scroll,
      saved.house_scroll
    ) == "full" then
      ctx:invalidate("full")
    else
      ctx:invalidate()
    end
  end
  return handled
end

return Runtime

end
__bundle["ui.view"] = function()
local Economy = require("domain.economy")
local Houses = require("domain.houses")
local Layout = require("ui.layout")

local View = {}
local GOODS = Economy.goods()
local HOUSE_CATALOG = Houses.catalog()
local WHITE, BLACK = 0, 15
local GOODS_ASSETS = {
  "01", "02", "03", "04", "05", "06", "07", "08",
}
local MAIN_ACTION_ASSETS = {
  market1 = "main_market1",
  market2 = "main_market2",
  market3 = "main_market3",
  bank = "main_bank",
  hospital = "main_hospital",
  houses = "main_houses",
  agency = "main_agency",
  help = "main_help",
  start_game = "main_start",
  records = "main_records",
}
-- 对话类弹层共用同一张豆包纸卡（agency_bg.xic，480x264）；买卖卡用竖版
-- trade_bg.xic（480x500）；成功页仍用 success_bg。素材缺省时 draw_overlay_frame
-- 会退回白底黑框。
local OVERLAY_FRAME_ASSETS = {
  new_game = "agency_bg",
  quit_game = "agency_bg",
  buy_goods = "trade_bg",
  sell_goods = "trade_bg",
  bank = "agency_bg",
  hospital = "agency_bg",
  agency = "agency_bg",
  price_note = "agency_bg",
  life_note = "agency_bg",
  sick_blackout = "agency_bg",
  sick_dead = "agency_bg",
  time_up = "agency_bg",
  sell_reputation = "agency_bg",
  no_money = "agency_bg",
  status = "agency_bg",
  buy_succ = "success_bg",
}
local OVERLAY_ACTION_ASSETS = {
  confirm_new_game = "new_game_start",
  close_overlay_new_game = "modal_cancel",
  confirm_quit_game = "quit_confirm",
  close_overlay_quit_game = "modal_cancel",
  confirm_buy = "trade_buy",
  confirm_sell = "trade_sell",
  close_overlay_trade = "trade_close",
  quantity_minus = "quantity_minus",
  quantity_plus = "quantity_plus",
  deposit_all = "bank_save",
  withdraw_all = "bank_withdraw",
  close_overlay_bank = "bank_leave",
  treat = "hospital_treat",
  close_overlay_hospital = "hospital_leave",
  expand = "agency_deal",
  close_overlay_agency = "agency_leave",
  confirm_overlay = "feedback_confirm",
}

-- Firmware treats g:image as a drawing command and may return no value.  The
-- browser bridge returns a boolean for missing assets, so only an explicit
-- false can select a primitive fallback; a nil result still means the image
-- command was submitted and must not be painted over.
local image_cache = {}
local draw_ctx

local function image_drawn(g, key, x, y, options)
  local ctx = draw_ctx
  if ctx == nil or type(key) ~= "string" then return false end
  local image = image_cache[key]
  if image == nil then
    image = ctx.package:image(key)
    image_cache[key] = image or false
  end
  if not image then return false end
  if options == nil then
    g:image(image, x, y)
  else
    g:image(image, x, y, options)
  end
  return true
end

View.STORY_PARAGRAPHS = {
  "    灯市散场后我蹲在摊边清账， 腿已经麻了， 脑子却还在转： 这样下去要转到哪一年？",
  "    来这座城四年， 合租、月光、借铺， 标签一层层贴着。 买下一处能关上门的房子， 真有那么远吗？",
  "    合租的已经捉急地在催房租了， 而我却还在算那本皱掉的账。",
  "    够了。 我要用一年把货做起来， 把钥匙拿到手。 灯市见， 我的家。",
  "    接下来的一年， 你要用身上仅有的3000块， 在夜市里低买高卖， 赚到几百万甚至上千万， 买下心仪的房子。 你能做到吗？",
}

View.HELP_EXPLANATIONS = {
  "    游戏目标： 在52周（一年）结束前赚到足够的钱买到房子。\n    这里显示房价和时间， 房价每周都会上涨。",
  "    这里是夜市货摊， 点击货物可以买入。\n    关键是摸清价格区间， 低买高卖。",
  "    这里是你的货仓， 买来的货物会放在这里。 点击货物可以卖出。\n    出租屋（70/100）表示已经放了70件， 一共100格， 还能再放30件。",
  "    这里显示现金、存款、健康和名声。\n    健康低于95， 你可能会累倒在摊边。\n    名声太差， 售楼处可能不把房子卖给你。",
  "    点这三个市场按钮， 货摊上的货物和价格会换一批， 时间也会过一周。",
  "    把多余的现金存进银行， 可以少损失， 每周还有利息。",
  "    在医院花钱看病， 能降低累倒的可能。",
  "    在售楼处能买到心仪的房子。",
  "    在中介花钱扩大货仓， 就能一次进更多货。",
}

local HOUSE_DESCRIPTIONS = {
  "    30平米的临街单间， 收摊后两个人住也够用。",
  "    巷口的80平米老屋， 虽旧， 但进出货方便。",
  "    灯市旁的新楼， 夜里亮堂， 适合把摊做稳的人。",
  "    180平米复式阁楼， 楼上住人， 楼下还能堆货。",
  "    280平米连排小院， 带一个小院， 家人来帮摊也住得下。",
  "    江岸位置稀缺， 夜里能看见灯市倒影的雅居。",
  "    城芯深处的府邸， 离夜市近， 却能关上门安静下来。",
  "    林间别院带泳池和花园， 适合把货做成事业的人。",
  "    小岛上的木屋， 有私家码头， 想歇多久歇多久。",
  "    建在星港的居所， 给把生意做到天边的人留的退路。",
}

local FONT_ADVANCE = {
  [32]=7, [33]=5, [34]=10, [35]=17, [36]=15, [37]=21, [38]=18, [39]=5,
  [40]=9, [41]=9, [42]=10, [43]=15, [44]=7, [45]=9, [46]=5, [47]=14,
  [48]=15, [49]=12, [50]=13, [51]=14, [52]=15, [53]=14, [54]=14, [55]=13,
  [56]=14, [57]=14, [58]=5, [59]=7, [60]=13, [61]=13, [62]=13, [63]=13,
  [64]=23, [65]=17, [66]=16, [67]=16, [68]=18, [69]=15, [70]=14, [71]=18,
  [72]=18, [73]=13, [74]=15, [75]=17, [76]=14, [77]=20, [78]=19, [79]=19,
  [80]=15, [81]=19, [82]=17, [83]=15, [84]=15, [85]=18, [86]=17, [87]=24,
  [88]=17, [89]=16, [90]=15, [91]=10, [92]=14, [93]=10, [94]=14, [95]=16,
  [96]=12, [97]=16, [98]=16, [99]=13, [100]=16, [101]=14, [102]=10, [103]=16,
  [104]=15, [105]=8, [106]=7, [107]=14, [108]=7, [109]=23, [110]=15, [111]=15,
  [112]=16, [113]=16, [114]=10, [115]=12, [116]=9, [117]=15, [118]=14, [119]=19,
  [120]=14, [121]=14, [122]=12, [123]=10, [124]=7, [125]=10, [126]=13,
}

function View.text_width(value)
  local width, index, text = 0, 1, tostring(value or "")
  while index <= #text do
    local byte = string.byte(text, index)
    if byte < 128 then
      width = width + (FONT_ADVANCE[byte] or 24)
      index = index + 1
    elseif byte == 0xC2 and string.byte(text, index + 1) == 0xB7 then
      width = width + 5
      index = index + 2
    else
      width = width + 24
      index = index + (byte < 224 and 2 or (byte < 240 and 3 or 4))
    end
  end
  return width
end

function View.fit_text(value, maximum)
  local text = tostring(value or "")
  if View.text_width(text) <= maximum then return text end
  local ellipsis, width, index, last = "…", 0, 1, 0
  while index <= #text do
    local byte = string.byte(text, index)
    local length = byte < 128 and 1 or (byte < 224 and 2 or (byte < 240 and 3 or 4))
    local chunk = string.sub(text, index, index + length - 1)
    local next_width = width + View.text_width(chunk)
    if next_width + View.text_width(ellipsis) > maximum then break end
    width, last, index = next_width, index + length - 1, index + length
  end
  if last == 0 then return "" end
  return string.sub(text, 1, last) .. ellipsis
end

function View.format_record_time(value)
  local text = tostring(value or "")
  local month, day, hour, minute = string.match(text, "^%d%d%d%d%-(%d%d)%-(%d%d)[ T](%d%d):(%d%d)")
  if month then return month .. "-" .. day .. " " .. hour .. ":" .. minute end
  return View.fit_text(text, 145)
end

local function house_asset_key(prefix, index)
  if type(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > 10 then return nil end
  return string.format(prefix .. "%02d", index)
end

function View.house_asset_key(index)
  return house_asset_key("house_", index)
end

function View.house_list_asset_key(index)
  return house_asset_key("house_list_", index)
end

function View.house_result_asset_key(index)
  return house_asset_key("house_result_", index)
end

function View.goods_icon_asset_key(goods_id)
  if type(goods_id) ~= "number" or goods_id ~= math.floor(goods_id) or goods_id < 1 or goods_id > 8 then
    return nil
  end
  return string.format("goods_icon_%02d", goods_id)
end

function View.goods_thumb_asset_key(goods_id)
  if type(goods_id) ~= "number" or goods_id ~= math.floor(goods_id) or goods_id < 1 or goods_id > 8 then
    return nil
  end
  return string.format("goods_thumb_%02d", goods_id)
end

local function keep_hand_art(base)
  return string.match(base, "^main_")
    or string.match(base, "^goods_")
    or string.match(base, "^cash_")
    or string.match(base, "^bank_")
    or string.match(base, "^hospital_")
    or string.match(base, "^agency_")
    or string.match(base, "^houses_")
    or base == "trade_buy"
    or base == "trade_sell"
end

local function state_asset_key(base, focused, disabled)
  if not base then return nil end
  -- 按下/禁用 XIC 在 1bpp 上会糊成黑块，主界面、货物、买卖确定和
  -- 银行/医院/中介/售楼部按钮仍用手绘正常稿。
  if focused and not keep_hand_art(base) then return base .. "_p" end
  if disabled and not keep_hand_art(base) then return base .. "_d" end
  return base
end

local LIST_DIGIT_SIZE = 16

local function draw_aligned(g, x, y, text, color, mode)
  text = tostring(text or "")
  local left = x
  if mode == "right" then
    left = x - View.text_width(text)
  elseif mode == "center" then
    left = x - View.text_width(text) / 2
  end
  g:text(math.floor(left), math.floor(y), text, { color = color or BLACK })
end

local function center(g, x, y, text, color, _size)
  draw_aligned(g, x, y, text, color, "center")
end

local function money(value)
  value = math.floor(tonumber(value) or 0)
  -- 十万元以下显示精确元数，避免 12600 被四舍五入成「1.3万」后看起来买得起 12635 的货。
  -- 更大金额按向下截断的一位小数缩写，绝不向上夸大。
  if value >= 100000000 then
    return string.format("%.1f亿", math.floor(value / 10000000) / 10)
  end
  if value >= 100000 then
    return string.format("%.1f万", math.floor(value / 1000) / 10)
  end
  return tostring(value)
end

-- 行情/买入价最多五位整数；不用「万」缩写，也不做省略裁剪。
local function list_price(value)
  value = math.floor(tonumber(value) or 0)
  if value < 0 then value = 0 end
  return tostring(value)
end

local function header(g, right)
  g:clear(WHITE)
  g:rect(14, 14, 452, 54, { fill = true, color = BLACK })
  g:text(28, 30, "白手买房", { color = WHITE })
  g:text(326, 30, right or "页面", { color = WHITE })
  g:line(14, 76, 466, 76, { color = BLACK })
  g:line(14, 81, 466, 81, { color = BLACK })
end

local function section_title(g, title, subtitle)
  g:text(24, 98, title, { color = BLACK })
  if subtitle then g:text(24, 124, subtitle, { color = BLACK }) end
end

local function button(g, item, focused)
  g:rect(item.x, item.y, item.w, item.h, { fill = focused and true or false, color = BLACK })
  center(g, item.x + item.w / 2, item.y + math.floor((item.h - 20) / 2), item.label, focused and WHITE or BLACK)
  if focused then
    g:circle(item.x + 15, math.floor(item.y + item.h / 2), 7, { color = WHITE })
  end
end

local function draw_actions(g, saved, skip_prefix)
  for index, item in ipairs(Layout.actions(saved)) do
    if not skip_prefix or not string.match(item.id, skip_prefix) then
      button(g, item, index == saved.focus)
    end
  end
end

local draw_wrapped_text
local draw_control
local draw_overlay_heading

local function draw_houses(g, saved)
  local page = Layout.ACTIVITIES.houses
  g:clear(WHITE)
  g:rect(page.head.x, page.head.y, page.head.w, page.head.h, { fill = true, color = BLACK })
  g:line(0, page.viewport.y, 480, page.viewport.y, { color = WHITE })
  g:rect(0, 718, 480, 82, { fill = true, color = WHITE })
  g:line(0, 718, 480, 718, { color = BLACK })
  center(g, page.title.x, page.title.y, "售楼部", WHITE)
  local page_no = math.floor((Layout.house_page_start(saved) - 1) / 2) + 1
  draw_aligned(g, 464, 18, tostring(page_no) .. "/5", WHITE, "right")
  g:text(
    page.money.x,
    page.money.y,
    "可用资金：" .. tostring(saved.game.cash + saved.game.deposit),
    { color = WHITE }
  )
  local fields = page.rowFields
  for _, row in ipairs(Layout.house_rows(saved)) do
    local house_index = row.house_index
    local house = HOUSE_CATALOG[house_index]
    local record = saved.records.houses[house_index]
    local selected = house_index == saved.game.selected_house
    local image = {
      x = row.x + fields.image.x,
      y = row.y + math.floor((row.h - fields.image.h) / 2),
      w = fields.image.w, h = fields.image.h,
    }
    g:rect(row.x, row.y, row.w, row.h, { fill = true, color = WHITE })
    g:rect(row.x, row.y, row.w, row.h, { color = BLACK })
    image_drawn(
      g,
      View.house_list_asset_key(house_index),
      image.x,
      image.y
    )
    g:rect(image.x, image.y, image.w, image.h, { color = BLACK })
    local text_y = image.y + 16
    local selection = {
      x = row.x + fields.selection.x, y = text_y - 8,
      w = fields.selection.w, h = fields.selection.h,
    }
    if selected then
      g:rect(selection.x, selection.y, selection.w, selection.h, { fill = true, color = BLACK })
    end
    center(
      g,
      row.x + fields.name.x + fields.name.w / 2,
      text_y,
      house.name,
      selected and WHITE or BLACK
    )
    g:text(
      row.x + fields.price.x,
      text_y + 40,
      "售价：" .. money(saved.game.house_prices[house_index]),
      { color = BLACK }
    )
    if record.success_count > 0 then
      g:text(
        row.x + fields.purchased.x,
        text_y + 40,
        "已购",
        { color = BLACK }
      )
    end
    draw_wrapped_text(
      g,
      row.x + fields.description.x,
      text_y + 76,
      HOUSE_DESCRIPTIONS[house_index],
      fields.description.w,
      24,
      math.max(1, math.floor(fields.description.h / 24))
    )
  end
  for index, item in ipairs(Layout.actions(saved)) do
    g:rect(item.x, item.y, item.w, item.h, { fill = true, color = WHITE })
    local base = nil
    if item.id == "house_buy" then base = "houses_buy"
    elseif item.id == "return_main" then base = "houses_leave" end
    draw_control(g, item, index == saved.focus, item.label, base)
  end
end

local function draw_records(g, saved)
  local page = Layout.ACTIVITIES.records
  g:clear(WHITE)
  g:rect(page.head.x, page.head.y, page.head.w, page.head.h, { fill = true, color = BLACK })
  if not image_drawn(g, "records_head", page.rows[1].x, page.rows[1].y) then
    g:line(0, page.rows[1].y, 480, page.rows[1].y, { color = WHITE })
  end
  g:rect(0, 718, 480, 82, { fill = true, color = WHITE })
  g:line(0, 718, 480, 718, { color = BLACK })
  center(g, page.title.x, page.title.y, "我的置业记录", WHITE)
  local first_center = page.columnWidths[1] / 2
  local second_center = page.columnWidths[1] + page.columnWidths[2] / 2
  local third_center = page.columnWidths[1] + page.columnWidths[2] + page.columnWidths[3] / 2
  center(g, first_center, page.columnsY, "房型", WHITE)
  center(g, second_center, page.columnsY, "首次购买时间", WHITE)
  center(g, third_center, page.columnsY, "成功次数", WHITE)
  local first_row, last_row = page.rows[1], page.rows[#page.rows]
  g:rect(first_row.x, first_row.y, first_row.w, last_row.y + last_row.h - first_row.y, { fill = true, color = WHITE })
  for index, rect in ipairs(page.rows) do
    local row = saved.records.houses[index]
    local y = rect.y
    if not image_drawn(g, "records_row" .. tostring(((index - 1) % 3) + 1), rect.x, rect.y) then
      g:rect(rect.x, rect.y, rect.w, rect.h, { fill = true, color = WHITE })
    end
    local name = View.fit_text(HOUSE_CATALOG[index].name, page.columnWidths[1] - 8)
    local first = View.format_record_time(row.first_success_at)
    local count = View.fit_text(tostring(row.success_count), page.columnWidths[3] - 8)
    center(g, first_center, y + 16, name, BLACK)
    center(g, second_center, y + 16, first, BLACK)
    center(g, third_center, y + 16, count, BLACK)
    g:line(rect.x, y + rect.h - 1, rect.x + rect.w, y + rect.h - 1, { color = BLACK })
  end
  for index, item in ipairs(Layout.actions(saved)) do
    draw_control(g, item, index == saved.focus, item.label, "records_leave")
  end
end

-- Task 5 can replace these primitive surfaces with XIC assets without moving
-- callers or changing any layout rectangle.
local function primitive_surface(g, rect)
  g:rect(rect.x, rect.y, rect.w, rect.h, { fill = true, color = WHITE })
  g:rect(rect.x, rect.y, rect.w, rect.h, { color = BLACK })
end

local function needs_label_overlay(base)
  if not base then return true end
  if string.match(base, "^goods_[mw]_") then return false end
  return true
end

local function overlay_control_label(g, item, label, color, inset, text_y)
  center(
    g,
    item.x + item.w / 2,
    text_y or (item.y + math.max(2, math.floor((item.h - 24) / 2))),
    View.fit_text(label, math.max(0, item.w - (inset or 0))),
    color
  )
end

draw_control = function(g, item, focused, label, asset_base)
  local active_focus = focused and not item.disabled
  local key = state_asset_key(asset_base, false, false)
  local enlarge_overlay_button = asset_base and (
    string.match(asset_base, "^bank_")
    or string.match(asset_base, "^hospital_")
    or string.match(asset_base, "^agency_")
  )
  local drawn = false
  if key and not enlarge_overlay_button and not active_focus then
    drawn = image_drawn(g, key, item.x, item.y)
  end
  if active_focus then
    g:rect(item.x, item.y, item.w, item.h, { fill = true, color = BLACK })
    if label and label ~= "" then
      overlay_control_label(g, item, label, WHITE, 8)
    end
    return true
  end
  if drawn then
    if label and label ~= "" and needs_label_overlay(asset_base) then
      overlay_control_label(
        g,
        item,
        label,
        BLACK,
        8,
        item.h >= 50 and (item.y + item.h - 26) or nil
      )
    end
    return true
  end
  g:rect(item.x, item.y, item.w, item.h, { fill = true, color = WHITE })
  g:rect(item.x, item.y, item.w, item.h, { color = BLACK })
  if label and label ~= "" then
    overlay_control_label(g, item, label, BLACK, 6)
  end
  return false
end

local function draw_goods_row(g, item, goods_id, name, focused)
  draw_control(g, item, focused, "")
  local icon = 32
  local thumb = goods_id and View.goods_thumb_asset_key(goods_id)
  local icon_x = item.x + 4
  local icon_y = item.y + math.floor((item.h - icon) / 2)
  if thumb then image_drawn(g, thumb, icon_x, icon_y) end
  if name and name ~= "" then
    g:text(
      icon_x + icon + 4,
      item.y + math.max(2, math.floor((item.h - 24) / 2)),
      View.fit_text(name, math.max(24, item.w - icon - 12)),
      { color = focused and WHITE or BLACK }
    )
  end
end

local function draw_main_header(g, game)
  local visual = Layout.MAIN_VISUAL
  local selected = game and game.selected_house or 1
  local price = game and game.house_prices and game.house_prices[selected]
  local header_rect = visual.header
  g:rect(header_rect.x, header_rect.y, header_rect.w, header_rect.h, { fill = true, color = BLACK })
  g:text(visual.header_house_label.x, visual.header_house_label.y, "房价：", { color = WHITE })
  g:text(visual.header_house_value.x, visual.header_house_value.y, price and money(price) or "—", { color = WHITE })
  g:text(visual.header_time_label.x, visual.header_time_label.y, "时间：", { color = WHITE })
  g:text(
    visual.header_time_value.x,
    visual.header_time_value.y,
    game and (tostring(game.week) .. "/52周") or "0/52周",
    { color = WHITE }
  )
end

local function draw_main_columns(g, saved, actions)
  local visual = Layout.MAIN_VISUAL
  local game = saved.game
  center(g, visual.market_title.x, visual.market_title.y, "市场", BLACK)
  local used = game and game.used or 0
  local capacity = game and game.capacity or 100
  center(
    g,
    visual.warehouse_title.x,
    visual.warehouse_title.y,
    "出租屋（" .. tostring(used) .. "/" .. tostring(capacity) .. "）",
    BLACK
  )
  local list = Layout.GOODS_LIST
  g:text(list.market_goods.x, list.market_goods.y, "货物", { color = BLACK })
  g:text(list.market_price.x, list.market_price.y, "价格", { color = BLACK })
  g:text(list.warehouse_goods.x, list.warehouse_goods.y, "货物", { color = BLACK })
  g:text(list.warehouse_price.x, list.warehouse_price.y, "买入价", { color = BLACK })
  g:text(list.warehouse_quantity.x, list.warehouse_quantity.y, "数量", { color = BLACK })

  for index = 1, 5 do
    local item = actions[index]
    local offer = game and game.market and game.market[index]
    local name = offer and GOODS[offer.goods_id] and GOODS[offer.goods_id].name or ""
    draw_goods_row(
      g,
      item,
      offer and offer.goods_id,
      name,
      saved.overlay == nil and saved.focus == index
    )
    if offer then
      local box = list.market_price_box
      center(
        g,
        box.x + box.w / 2,
        item.y + math.max(2, math.floor((item.h - 24) / 2)),
        list_price(offer.price),
        BLACK,
        LIST_DIGIT_SIZE
      )
    end
  end

  for index = 1, 5 do
    local action_index = index + 5
    local item = actions[action_index]
    local slot = game and game.inventory and game.inventory[index]
    local name = slot and GOODS[slot.goods_id] and GOODS[slot.goods_id].name or ""
    if slot then
      local focused = saved.overlay == nil and saved.focus == action_index
      local ink = focused and WHITE or BLACK
      draw_control(g, item, focused, "")
      local icon = 32
      local icon_x = item.x + 4
      local thumb = View.goods_thumb_asset_key(slot.goods_id)
      if thumb then
        image_drawn(g, thumb, icon_x, item.y + list.warehouse_name_y)
      end
      local name_x = icon_x + icon + 4
      g:text(
        name_x,
        item.y + list.warehouse_name_y,
        View.fit_text(name, math.max(24, item.x + item.w - name_x - 8)),
        { color = ink }
      )
      local value_y = item.y + list.warehouse_value_y
      draw_aligned(g, list.warehouse_price_right, value_y, list_price(slot.average_cost), ink, "right")
      draw_aligned(g, list.warehouse_quantity_right, value_y, tostring(slot.quantity), ink, "right")
    elseif not game then
      draw_control(g, item, false, "")
    end
  end
end

local function draw_column_divider(g)
  local spec = Layout.COLUMN_DIVIDER
  local band = Layout.status_band()
  local bottom = math.min(spec.bottom, band.y)
  g:rect(spec.x - 4, spec.y, 8, bottom - spec.y, { fill = true, color = WHITE })
  g:line(spec.x, spec.y, spec.x, bottom, { color = BLACK })
end

local function draw_status_divider(g, y)
  local x = 8
  while x < 472 do
    g:rect(x, y, 10, 2, { fill = true, color = WHITE })
    x = x + 16
  end
end

local function draw_main_status(g, game)
  local visual = Layout.MAIN_VISUAL
  local cash = game and money(game.cash) or "—"
  local health = game and tostring(game.health) or "—"
  local deposit = game and money(game.deposit) or "—"
  local reputation = game and tostring(game.reputation) or "—"
  local cash_rect = Layout.MAIN.status_cash
  local deposit_rect = Layout.MAIN.status_deposit
  local band = Layout.status_band()
  local shift = band.shift
  local top = band.y
  if not image_drawn(g, "status_1_bg", 0, top) then
    g:rect(cash_rect.x, top, cash_rect.w, cash_rect.h, { fill = true, color = BLACK })
  end
  if not image_drawn(g, "status_2_bg", 0, deposit_rect.y + shift) then
    g:rect(deposit_rect.x, deposit_rect.y + shift, deposit_rect.w, deposit_rect.h, { fill = true, color = BLACK })
  end
  g:rect(cash_rect.x, top, cash_rect.w, band.h, { fill = true, color = BLACK })
  draw_status_divider(g, deposit_rect.y + shift - 3)
  g:text(visual.status_cash_label.x, visual.status_cash_label.y + shift, "现金：", { color = WHITE })
  g:text(visual.status_cash_value.x, visual.status_cash_value.y + shift, cash, { color = WHITE })
  g:text(visual.status_health_label.x, visual.status_health_label.y + shift, "健康：", { color = WHITE })
  g:text(visual.status_health_value.x, visual.status_health_value.y + shift, health, { color = WHITE })
  g:text(visual.status_deposit_label.x, visual.status_deposit_label.y + shift, "存款：", { color = WHITE })
  g:text(visual.status_deposit_value.x, visual.status_deposit_value.y + shift, deposit, { color = WHITE })
  g:text(visual.status_reputation_label.x, visual.status_reputation_label.y + shift, "名声：", { color = WHITE })
  g:text(visual.status_reputation_value.x, visual.status_reputation_value.y + shift, reputation, { color = WHITE })
end

local function draw_main_actions(g, saved, actions)
  for index = #actions, 11, -1 do
    local item = actions[index]
    local base = MAIN_ACTION_ASSETS[item.id]
    if item.id == "start_game" and saved.game and saved.game.status == "playing" then
      base = "main_end"
    end
    draw_control(g, item, saved.overlay == nil and saved.focus == index, item.label, base)
  end
end

local function draw_main(g, saved)
  g:clear(WHITE)
  local actions = Layout.actions({
    screen = "main",
    game = saved.game,
    current_market = saved.current_market,
  })
  local playing = saved.game and saved.game.status == "playing"
  draw_main_header(g, playing and saved.game or nil)
  if not playing then
    if not saved.focus or saved.focus < 1 or saved.focus > #actions then
      saved.focus = 1
    end
    g:text(40, 148, "还没开始", { color = BLACK })
    draw_wrapped_text(
      g, 40, 196,
      "先点下面的「开始游戏」。没开局之前，市场、银行和医院都不能用。",
      400, 32, 3
    )
    g:text(40, 312, "本金 3000，一年 52 周。", { color = BLACK })
    for index, item in ipairs(actions) do
      local focused = saved.focus == index
      if item.id == "start_game" then
        g:rect(item.x, item.y, item.w, item.h, { fill = true, color = BLACK })
        if focused then
          g:rect(item.x + 6, item.y + 6, item.w - 12, item.h - 12, { color = WHITE })
        end
        overlay_control_label(g, item, item.label, WHITE, 8)
      else
        draw_control(g, item, focused, item.label, nil)
      end
    end
    return
  end
  if not image_drawn(g, "main_bg", 0, 60) then
    g:rect(0, 60, 480, 395, { fill = true, color = WHITE })
  end
  local band = Layout.status_band()
  g:rect(0, 92, 480, math.max(0, band.y - 92), { fill = true, color = WHITE })
  draw_column_divider(g)
  draw_main_columns(g, saved, actions)
  draw_main_status(g, saved.game)
  local hide_footer = saved.overlay ~= nil and saved.overlay.kind ~= "help_mask"
  if hide_footer then
    g:rect(0, band.y, 480, 800 - band.y, { fill = true, color = WHITE })
  else
    draw_main_actions(g, saved, actions)
  end
end

local XML_TEXT_OVERLAY = {
  price_note = true,
  life_note = true,
  sick_blackout = true,
  sick_dead = true,
  time_up = true,
  sell_reputation = true,
  no_money = true,
  status = true,
  buy_succ = true,
}

local function wrapped_lines(value, maximum, maximum_lines)
  local text = tostring(value or "")
  local line, line_width, index, lines = "", 0, 1, {}
  while index <= #text and #lines < maximum_lines do
    local byte = string.byte(text, index)
    if byte == 10 then
      lines[#lines + 1], line, line_width = line, "", 0
      index = index + 1
    else
    local length = byte < 128 and 1 or (byte < 224 and 2 or (byte < 240 and 3 or 4))
    local chunk = string.sub(text, index, index + length - 1)
    local width = View.text_width(chunk)
    if line ~= "" and line_width + width > maximum then
      lines[#lines + 1], line, line_width = line, "", 0
    end
    if #lines < maximum_lines then
      line, line_width = line .. chunk, line_width + width
    end
    index = index + length
    end
  end
  if line ~= "" and #lines < maximum_lines then lines[#lines + 1] = line end
  return lines
end

function View.success_text_pages(value)
  local text = Layout.modal_visual("buy_succ").text
  local maximum_lines = math.max(1, math.floor(text.h / text.lineHeight))
  local lines = wrapped_lines(value, text.w, math.huge)
  local pages = {}
  for first = 1, #lines, maximum_lines do
    pages[#pages + 1] = table.concat(
      lines,
      "\n",
      first,
      math.min(#lines, first + maximum_lines - 1)
    )
  end
  if #pages == 0 then pages[1] = "" end
  return pages
end

draw_wrapped_text = function(g, x, y, value, maximum, line_height, maximum_lines, color)
  for index, line in ipairs(wrapped_lines(value, maximum, maximum_lines)) do
    g:text(x, y + (index - 1) * line_height, line, { color = color or BLACK })
  end
end

local function draw_bottom_centered_text(g, visual, value)
  local lines = wrapped_lines(value, visual.w, math.huge)
  local first_y = visual.bottom - #lines * visual.lineHeight
  for index, line in ipairs(lines) do
    center(g, visual.centerX, first_y + (index - 1) * visual.lineHeight, line, BLACK)
  end
end

local function overlay_goods(saved)
  local overlay = saved.overlay
  local game = saved.game
  if not game then return "货物", nil end
  local source = overlay.kind == "buy_goods"
    and game.market and game.market[overlay.index]
    or game.inventory and game.inventory[overlay.index]
  if not source then return "货物", nil end
  local goods = GOODS[source.goods_id]
  return goods and goods.name or "货物", source
end

local function draw_overlay_actions(g, saved, actions)
  for index, item in ipairs(actions) do
    local kind = saved.overlay.kind
    local lookup = item.id
    if item.id == "close_overlay" then
      if kind == "new_game" then lookup = "close_overlay_new_game"
      elseif kind == "quit_game" then lookup = "close_overlay_quit_game"
      elseif kind == "buy_goods" or kind == "sell_goods" then lookup = "close_overlay_trade"
      else lookup = "close_overlay_" .. kind end
    end
    draw_control(
      g,
      item,
      saved.overlay_focus == index,
      item.label,
      OVERLAY_ACTION_ASSETS[lookup]
    )
  end
end

-- 备注卡绘制：卡面已由 draw_overlay_frame 画好，这里把标题写进挂牌、正文
-- 自动换行、卡底放实心「确认」。整张卡仍是点击热区，所以点按钮或点卡片
-- 任意位置都会确认并进到下一条消息。
local function draw_note_card(g, saved, visual)
  local frame = Layout.overlay_frame(saved.overlay.kind)
  if not frame then return end
  local title = tostring(saved.overlay.title or "")
  if title ~= "" then
    center(g, CARD.plate.cx, CARD.plate.y, View.fit_text(title, 128), BLACK)
  end
  local text = visual.text
  local maximum_lines = math.max(1, math.floor(text.h / text.lineHeight))
  draw_wrapped_text(
    g,
    text.x,
    text.y,
    saved.overlay.text or "",
    text.w,
    text.lineHeight,
    maximum_lines
  )
  local spec = visual.button
  button(g, {
    x = spec.x,
    y = spec.y,
    w = spec.w,
    h = spec.h,
    label = spec.label or "确认",
  }, true)
end

local function draw_xml_text_overlay(g, saved, visual, actions)
  if visual.button then
    draw_note_card(g, saved, visual)
    return
  end
  if visual.image then
    g:rect(visual.image.x, visual.image.y, visual.image.w, visual.image.h, { color = BLACK })
    local house_index = saved.game and saved.game.selected_house
    local asset = saved.overlay.kind == "buy_succ"
      and View.house_result_asset_key(house_index)
    if asset then
      image_drawn(g, asset, visual.image.x, visual.image.y)
    end
  end
  local text = visual.text
  local maximum_lines = text.h and math.max(1, math.floor(text.h / text.lineHeight)) or 8
  local value = saved.overlay.text or "请确认"
  if saved.overlay.kind == "buy_succ" then
    local pages = View.success_text_pages(value)
    value = pages[math.max(1, math.min(#pages, saved.overlay.page or 1))]
  end
  draw_wrapped_text(
    g,
    text.x,
    text.y,
    value,
    text.w,
    text.lineHeight,
    maximum_lines
  )
  if saved.overlay.kind == "no_money" or saved.overlay.kind == "status"
      or saved.overlay.kind == "buy_succ" then
    draw_overlay_actions(g, saved, actions)
  end
end

local function market_price(game, goods_id)
  for _, offer in ipairs(game.market or {}) do
    if offer.goods_id == goods_id then return offer.price end
  end
  return nil
end

local function sell_guidance(game, slot, quantity)
  local price = game and slot and market_price(game, slot.goods_id)
  if not price then return "市场中没有这种货物， 你无法出售" end
  local projected = (price - slot.average_cost) * quantity
  if projected < 0 then return "卖出会亏损 " .. money(-projected) end
  return "卖出可盈利 " .. money(projected)
end

local function draw_trade_overlay(g, saved, actions)
  local kind = saved.overlay.kind
  local frame = Layout.overlay_frame(kind)
  local name, source = overlay_goods(saved)
  local game = saved.game
  local trade = CARD.trade
  center(g, trade.plate.cx, trade.plate.y, kind == "sell_goods" and "卖出" or "买入", BLACK)
  if game then
    g:text(frame.x + 24, trade.fundsY, "现金 " .. money(game.cash), { color = BLACK })
    draw_aligned(g, frame.x + frame.w - 24, trade.fundsY, "存款 " .. money(game.deposit), BLACK, "right")
  end
  local picture = 112
  local picture_x = frame.x + 24
  local picture_y = trade.pictureY
  g:rect(picture_x - 4, picture_y - 4, picture + 8, picture + 8, { color = BLACK })
  local goods_id = source and source.goods_id
  local icon_key = goods_id and View.goods_icon_asset_key(goods_id)
  if not icon_key or not image_drawn(g, icon_key, picture_x, picture_y) then
    g:rect(picture_x, picture_y, picture, picture, { fill = true, color = WHITE })
  end
  local text_x = picture_x + picture + 20
  local text_w = frame.w - (text_x - frame.x) - 24
  g:text(text_x, picture_y + 4, View.fit_text(name, text_w), { color = BLACK })
  local unit = source and (source.price or source.average_cost)
  if unit then
    g:text(text_x, picture_y + 44, "单价 " .. tostring(unit), { color = BLACK })
  end
  local hint
  if kind == "buy_goods" then
    hint = "最多可买 " .. tostring(Layout.buy_maximum(saved)) .. " 个"
  elseif source then
    hint = sell_guidance(saved.game, source, saved.quantity)
  end
  if hint then
    draw_wrapped_text(g, text_x, picture_y + 76, hint, text_w, 28, 2)
  end
  local metrics = Layout.trade_metrics
  g:text(frame.x + 24, metrics.qty_y + 24, "数量", { color = BLACK })
  g:rect(204, metrics.qty_y, 64, metrics.qty_h, { color = BLACK })
  center(g, 236, metrics.qty_y + 24, tostring(saved.quantity), BLACK)
  for index, item in ipairs(actions) do
    if not string.match(item.id, "_qty_") or item.y == metrics.shortcut_y then
      draw_control(g, item, saved.overlay_focus == index, item.label, nil)
    end
  end
end

-- 现金/存款一律右对齐写在卡面标题行里（挂牌右边），不再有浮在卡外、缝隙里
-- 漏行情字的那条横条；金额太长时退回只报总额。
local function card_funds_text(game, maximum)
  local funds = "现金：" .. money(game.cash) .. "  存款：" .. money(game.deposit)
  if View.text_width(funds) > maximum then
    funds = "可用：" .. money(game.cash + game.deposit)
  end
  return funds
end

-- 标题统一写进卡面左上那块挂牌，正文从挂牌下面 490 起自动换行。
draw_overlay_heading = function(g, frame, title, body)
  if not frame then return end
  center(g, CARD.plate.cx, CARD.plate.y, title, BLACK)
  if body then
    draw_wrapped_text(
      g,
      CARD.text.x,
      CARD.text.y,
      body,
      CARD.text.w,
      CARD.text.lineHeight,
      CARD.text.maxLines
    )
  end
end

local function draw_actionable_overlay(g, saved, actions)
  local kind = saved.overlay.kind
  local visual = Layout.modal_visual(kind)
  local frame = Layout.overlay_frame(kind)
  if kind == "new_game" then
    draw_overlay_heading(
      g,
      frame,
      "开始游戏",
      "从3000块本金开始， 在夜市里做一年买卖。"
    )
    if visual.icon then
      image_drawn(g, "cash_icon", visual.icon.x, visual.icon.y)
    end
    g:text(visual.cash.x, visual.cash.y, "本金 3000", { color = BLACK })
  elseif kind == "quit_game" then
    draw_overlay_heading(
      g,
      frame,
      "结束游戏",
      "确定结束本局？ 当前进度不会保留。"
    )
  elseif kind == "bank" then
    draw_overlay_heading(
      g,
      frame,
      "银行",
      "现金存进银行少损失， 每周还有利息。 点存钱全存， 点取钱全取。"
    )
  elseif kind == "hospital" then
    local game = saved.game
    local health = game and game.health or 0
    local cost = math.max(0, (100 - health) * 5000)
    local funds = game and game.cash + game.deposit or 0
    local guidance
    if health >= 100 then
      guidance = "身体好好的来医院干啥， 赶紧干正事儿去吧。"
    elseif funds < cost then
      guidance = "看病需要花费" .. tostring(cost) .. "元， 你没有足够的钱看病！"
    else
      guidance = "看病需要花费" .. tostring(cost) .. "元， 确定要看病吗？"
    end
    draw_overlay_heading(g, frame, "医院", guidance)
  elseif kind == "agency" then
    local game = saved.game or {}
    -- 标题钉在卡面左上的挂牌里，资金跟在同一行右侧。
    center(g, visual.title.cx, visual.title.y, "中介", BLACK)
    draw_aligned(
      g,
      visual.funds.right,
      visual.funds.y,
      card_funds_text(game, visual.funds.w),
      BLACK,
      "right"
    )
    center(g, visual.prefix.x + visual.prefix.w / 2, visual.prefix.y, "增加", BLACK)
    center(g, visual.suffix.x + visual.suffix.w / 2, visual.suffix.y, "个出租屋空间", BLACK)
    g:rect(visual.input.x, visual.input.y, visual.input.w, visual.input.h, { fill = true, color = WHITE })
    g:rect(visual.input.x, visual.input.y, visual.input.w, visual.input.h, { color = BLACK })
    center(
      g,
      visual.input.x + visual.input.w / 2,
      visual.input.y + visual.fieldTextOffsetY,
      tostring(saved.quantity),
      BLACK
    )
    center(
      g,
      visual.note.centerX,
      visual.note.y,
      "共需要花费" .. money(saved.quantity * 10000) .. "元",
      BLACK
    )
  end
  draw_overlay_actions(g, saved, actions)
end

local function draw_overlay_frame(g, kind, frame, background)
  -- 先铺白底，再按 1:1 贴卡面素材（XIC 不能缩放）。现在每张卡面都按 frame
  -- 原尺寸生成（中介/服务卡 480x264、买卖卡 480x500），没有需要补白的余高；
  -- 没有素材的老卡（成功页）才退回黑框。
  g:rect(frame.x, frame.y, frame.w, frame.h, { fill = true, color = WHITE })
  local drawn = background and image_drawn(g, background, frame.x, frame.y)
  if not drawn then
    g:rect(frame.x, frame.y, frame.w, frame.h, { color = BLACK })
  end
end

local function draw_overlay_funds(g, saved)
  local game = saved.game
  local kind = saved.overlay and saved.overlay.kind
  if not game then return end
  if kind ~= "bank" and kind ~= "hospital" and kind ~= "quit_game" then return end
  draw_aligned(
    g,
    CARD.funds.right,
    CARD.funds.y,
    card_funds_text(game, CARD.funds.w),
    BLACK,
    "right"
  )
end

local function draw_overlay(g, saved)
  local overlay = saved.overlay
  if type(overlay) ~= "table" then return end
  if overlay.kind == "help_mask" then return end
  local frame = Layout.overlay_frame(overlay.kind)
  if not frame then return end
  local actions = Layout.overlay_actions(saved)
  local background = OVERLAY_FRAME_ASSETS[overlay.kind]
  draw_overlay_frame(g, overlay.kind, frame, background)
  draw_overlay_funds(g, saved)
  if XML_TEXT_OVERLAY[overlay.kind] then
    draw_xml_text_overlay(g, saved, Layout.modal_visual(overlay.kind), actions)
  elseif overlay.kind == "buy_goods" or overlay.kind == "sell_goods" then
    draw_trade_overlay(g, saved, actions)
  else
    draw_actionable_overlay(g, saved, actions)
  end
end

local function draw_story(g, saved)
  local page = Layout.ACTIVITIES.story
  local step = math.max(1, math.min(5, saved.story_step or 1))
  g:clear(WHITE)
  if not image_drawn(g, "story_bg", 0, 320) then
    g:rect(0, 320, 480, 480, { fill = true, color = WHITE })
  end
  draw_wrapped_text(
    g,
    page.text.x,
    page.text.y,
    View.STORY_PARAGRAPHS[step],
    page.text.w,
    26,
    math.floor(page.text.h / 26)
  )
  for index, item in ipairs(Layout.actions(saved)) do
    local base = item.id == "finish_story" and "story_start" or "story_continue"
    draw_control(g, item, index == saved.focus, item.label, base)
  end
end

local function fill_if_positive(g, x, y, w, h, color)
  if w > 0 and h > 0 then g:rect(x, y, w, h, { fill = true, color = color }) end
end

local function mask_except(g, rect)
  fill_if_positive(g, 0, 0, 480, rect.y, BLACK)
  fill_if_positive(g, 0, rect.y, rect.x, rect.h, BLACK)
  fill_if_positive(g, rect.x + rect.w, rect.y, 480 - rect.x - rect.w, rect.h, BLACK)
  fill_if_positive(g, 0, rect.y + rect.h, 480, 800 - rect.y - rect.h, BLACK)
end

local function draw_help(g, saved)
  local sample = {
    screen = "main",
    overlay = { kind = "help_mask" },
    focus = 1,
    current_market = 1,
    game = {
      week = 28,
      cash = 0,
      deposit = 734738,
      health = 96,
      reputation = 98,
      capacity = 100,
      used = 70,
      selected_house = 1,
      status = "playing",
      house_prices = { 259, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
      market = {
        { goods_id = 5, price = 397 },
        { goods_id = 2, price = 137 },
        { goods_id = 6, price = 3457 },
        { goods_id = 7, price = 106 },
        { goods_id = 4, price = 674 },
      },
      inventory = {
        { goods_id = 8, quantity = 50, average_cost = 15023 },
        { goods_id = 6, quantity = 20, average_cost = 2065 },
      },
    },
  }
  draw_main(g, sample)
  local page = Layout.ACTIVITIES.help
  local step = math.max(1, math.min(9, saved.help_step or 1))
  local highlight = Layout.help_highlights()[step]
  mask_except(g, highlight)
  g:rect(highlight.x, highlight.y, highlight.w, highlight.h, { color = BLACK })
  local explanation = page.explanation
  if highlight.y < explanation.y + explanation.h and highlight.y + highlight.h > explanation.y then
    if highlight.y >= 480 then
      explanation = { x = 40, y = 200, w = 400, h = 160, lineHeight = 24 }
    elseif highlight.x + highlight.w <= 240 then
      explanation = { x = 248, y = 140, w = 220, h = 220, lineHeight = 24 }
    else
      explanation = { x = 16, y = 140, w = 200, h = 220, lineHeight = 24 }
    end
  end
  g:rect(explanation.x, explanation.y, explanation.w, explanation.h, { fill = true, color = BLACK })
  draw_wrapped_text(
    g,
    explanation.x + 8,
    explanation.y + 8,
    View.HELP_EXPLANATIONS[step],
    explanation.w - 16,
    explanation.lineHeight,
    12,
    WHITE
  )
  for index, item in ipairs(Layout.actions(saved)) do
    draw_control(g, item, index == saved.focus, item.label)
  end
end

function View.draw(ctx, g, saved)
  draw_ctx = ctx
  if saved.screen == "houses" then draw_houses(g, saved)
  elseif saved.screen == "records" then draw_records(g, saved)
  elseif saved.screen == "help" then draw_help(g, saved)
  elseif saved.screen == "story" then draw_story(g, saved)
  else draw_main(g, saved) end
  draw_overlay(g, saved)
end

return View

end
local Runtime = require("ui.runtime")
local View = require("ui.view")

function on_load(ctx)
  Runtime.boot(ctx)
end

function on_input(ctx, ev)
  return Runtime.input(ctx, ev)
end

function on_draw(ctx, g)
  View.draw(ctx, g, Runtime.state(ctx))
end
