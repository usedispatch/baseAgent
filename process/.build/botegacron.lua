do
    local _ENV = _ENV
    package.preload[ "agent.agent" ] = function( ... ) local arg = _G.arg;
    local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local os = _tl_compat and _tl_compat.os or os; local pairs = _tl_compat and _tl_compat.pairs or pairs; require("agent.globals")
    require("agent.strategies.globals")
    
    local limitOrderStrategy = require("agent.strategies.limit-order")
    local stopOrderStrategy = require("agent.strategies.stop-order")
    local dcaOrderStrategy = require("agent.strategies.dca-order")
    
    local bint = require("utils.tl-bint")(256)
    local json = require("json")
    
    PricePrecision = 18
    Status = Status or "AwaitingStrategyConfiguration"
    LatestReserveUpdate = LatestReserveUpdate or nil
    local TriggerType = 'Swap'
    
    assert(ao.env.Process.Tags.Amm, "Process Tag 'Amm' is required")
    assert(ao.env.Process.Tags["Amm-Factory"], "Process Tag 'Amm-Factory' is required")
    assert(ao.env.Process.Tags["Order-Owner"], "Process Tag 'Order-Owner' is required")
    assert(ao.env.Process.Tags["Token-From"], "Process Tag 'Token-From' is required")
    assert(ao.env.Process.Tags["Token-To"], "Process Tag 'Token-To' is required")
    assert(ao.env.Process.Tags["Input"], "Process Tag 'Input' is required")
    assert(ao.env.Process.Tags["Expires-At"], "Process Tag 'Expires-At' is required")
    assert(ao.env.Process.Tags["Agent-Type"], "Process Tag 'Agent-Type' is required")
    
    ProcessCfg = {
       Dexi = ao.env.Process.Tags.Dexi or nil,
       Amm = ao.env.Process.Tags.Amm,
       AmmFactory = ao.env.Process.Tags["Amm-Factory"],
       AgentFactory = ao.env.Process.Tags["Agent-Factory"],
       OrderOwner = ao.env.Process.Tags["Order-Owner"],
       ExpiresAt = tonumber(ao.env.Process.Tags["Expires-At"]),
       AgentType = ao.env.Process.Tags["Agent-Type"],
       Input = ao.env.Process.Tags["Input"],
       TokenFrom = ao.env.Process.Tags["Token-From"],
       TokenTo = ao.env.Process.Tags["Token-To"],
       CronInterval = ao.env.Process.Tags["Cron-Interval"],
    }
    
    HasPendingCancellation = HasPendingCancellation or false
    
    SwapsModule = require("agent.swaps")
    
    if ProcessCfg.AgentType == 'limit-order' then
       TriggerType = 'Swap'
       Strat = limitOrderStrategy()
    elseif ProcessCfg.AgentType == 'stop-order' then
       TriggerType = 'Swap'
       Strat = stopOrderStrategy()
    elseif ProcessCfg.AgentType == 'dca-order' then
       TriggerType = 'Cron'
       Strat = dcaOrderStrategy()
    else
       error("Agent-Type '" .. ProcessCfg.AgentType .. "' is not supported. Valid options are: 'limit-order', 'dca-order', 'stop-order' ")
    end
    
    
    local agent = {}
    
    
    
    
    
    
    local function getInfo()
       local strategyInfo = Strat.ConfigMsg and Strat.getInfo()
       return {
          full = {
             ["Agent-Type"] = ProcessCfg.AgentType,
             ["Status"] = Status,
             ["Token-From"] = ProcessCfg.TokenFrom,
             ["Token-To"] = ProcessCfg.TokenTo,
             ["Input"] = tostring(ProcessCfg.Input),
             ["Expires-At"] = tostring(ProcessCfg.ExpiresAt),
             ["Order-Owner"] = ProcessCfg.OrderOwner,
             ["Has-Pending-Cancellation"] = tostring(HasPendingCancellation),
             ["Strategy"] = strategyInfo and strategyInfo.full,
          },
          rootTags = strategyInfo and strategyInfo.rootTags or {},
       }
    end
    
    local function getProgressUpdateInfo()
       local agentInfo = getInfo()
       local info = agentInfo.full
       local strategyInfo = info.Strategy
       info.Data = json.encode(strategyInfo)
       info.Strategy = nil
    
    
       for tag, value in pairs(agentInfo.rootTags) do
          info[tag] = value
       end
    
       return info
    end
    
    function agent.getBalances()
       ao.send({
          Target = ProcessCfg.TokenFrom,
          Action = "Balance",
       })
    
       local responseTkFrom = Receive(function(m)
          return m.Tags['From-Process'] == ProcessCfg.TokenFrom and m.Tags.Balance ~= nil
       end)
    
       ao.send({
          Target = ProcessCfg.TokenTo,
          Action = "Balance",
       })
    
       local responseTkTo = Receive(function(m)
          return m.Tags['From-Process'] == ProcessCfg.TokenTo and m.Tags.Balance ~= nil
       end)
    
       return {
          Input = bint(responseTkFrom.Tags.Balance),
          Output = bint(responseTkTo.Tags.Balance),
       }
    end
    
    
    
    function agent.refundCredit(sender, quantity, reason)
       ao.send({
          Target = ProcessCfg.TokenFrom,
          Action = "Transfer",
          Recipient = sender,
          Quantity = quantity,
       })
    
       ao.send({
          Target = sender,
          Action = "Refund-Notice",
          Quantity = quantity,
          Reason = reason,
       })
    end
    
    
    
    function agent.sendOrderOwnerFunds(xAction, explicitBalances)
       local balances = explicitBalances or agent.getBalances()
       if bint.ispos(balances.Output) then
          ao.send({
             Target = ProcessCfg.TokenTo,
             Action = "Transfer",
             Recipient = ProcessCfg.OrderOwner,
             Quantity = tostring(balances.Output),
             ["X-Action"] = xAction,
          })
       end
    
       if bint.ispos(balances.Input) then
          ao.send({
             Target = ProcessCfg.TokenFrom,
             Action = "Transfer",
             Recipient = ProcessCfg.OrderOwner,
             Quantity = tostring(balances.Input),
             ["X-Action"] = xAction,
          })
       end
    end
    
    local function unsubscribe()
       ao.send({
          Target = ProcessCfg.Dexi,
          Action = "Unsubscribe-Reserve-Changes",
          ["Process-Id"] = ao.id,
          ["Amm-Process-Id"] = ProcessCfg.Amm,
       })
    end
    
    local function notifyBackendFinalized()
       ao.send({
          Target = Owner,
          Action = 'Finalized-Agent',
          Status = Status,
       })
    end
    
    local function notifyOrderOwner(action)
       local notification = getProgressUpdateInfo()
    
    
       notification.Target = ProcessCfg.AgentFactory
       notification.Action = action
       notification["Relay-To"] = ProcessCfg.OrderOwner
       notification["Trigger-Timestamp"] = tostring(os.time())
    
       ao.send(notification)
    end
    
    
    
    
    
    
    
    
    
    
    local function notifyOrderOwnerFinalized()
       local action = Status == 'Complete' and 'Botega-Order-Confirmation' or 'Botega-Order-Error'
       notifyOrderOwner(action)
    end
    
    function agent.finalize(cfg)
       if not cfg.skipFundsTransfer then
          agent.sendOrderOwnerFunds(cfg.xAction)
       end
    
       unsubscribe()
    
       notifyBackendFinalized()
    
       notifyOrderOwnerFinalized()
    end
    
    function agent.completeAsExpired()
       Status = 'Expired'
       agent.finalize({ xAction = 'Expiration' })
    end
    
    function agent.cancelStrategy()
       if Status == 'AwaitingDeposit' or
          Status == 'AwaitingStrategyConfiguration' or
          Status == 'AwaitingSubscription' or
          Status == 'Ready' then
    
          Status = 'Canceled'
          agent.finalize({ xAction = 'Cancellation' })
       elseif Status == 'Swapping' then
          if TriggerType == 'Swap' then
             HasPendingCancellation = true
             print('set pending cancellation')
          else
    
    
             Status = 'Canceled'
             agent.finalize({ xAction = 'Cancellation' })
          end
       elseif Status == 'Complete' or Status == 'Expired' or Status == 'Canceled' or Status == 'EmergencyExited' then
          error('Cannot cancel in this state: ' .. Status)
       else
          error('Missed value in cancelStrategy() case check')
       end
    end
    
    
    
    function agent._handleAmmUpdate(msg)
       if Status == "Swapping" then
          print("Status is 'Swapping' - skipping the params update check")
          return
       end
    
       if Status ~= "Ready" then
          print("Status is not 'Ready' but " .. Status .. " - skipping the params update check")
          return
       end
    
       if ProcessCfg.ExpiresAt < tonumber(msg.Timestamp) then
          agent.completeAsExpired()
          return
       end
    
    
    
       local ammUpdateResult = Strat.handleAmmUpdate(msg)
    
    
    
    
    
    
    
       print('Strategy finished handling AMM Update with result: ' .. ammUpdateResult.swapResult)
       local regularWrapUp = true
       if ammUpdateResult.swapResult == "SuccessfulSwap" then
    
    
          regularWrapUp = Status ~= 'EmergencyExited'
       elseif ammUpdateResult.swapResult == "FailedSwap" then
          if Status == 'EmergencyExited' then
    
             agent.sendOrderOwnerFunds('Post-Emergency-Withdrawal-Refund')
          elseif HasPendingCancellation then
    
             Status = "Ready"
             agent.cancelStrategy()
          elseif LatestReserveUpdate then
             Status = "Ready"
    
             local isRecentUpdate = tonumber(LatestReserveUpdate.Timestamp) > LastSwapAttemptTimestamp
             local isNotExpired = ProcessCfg.ExpiresAt >= tonumber(msg.Timestamp)
             local isNotDCA = TriggerType == 'Swap'
    
             if isRecentUpdate and isNotDCA and isNotExpired then
                print('Recent reserve update available - directly attempting new handleAmmUpdate')
    
    
    
    
    
    
    
                agent._handleAmmUpdate(LatestReserveUpdate)
                LatestReserveUpdate = nil
             end
          else
    
    
             Status = "Ready"
          end
    
    
    
          regularWrapUp = false
       end
    
    
    
       if regularWrapUp then
          print('Regular Wrap Up')
          Status = ammUpdateResult.nextAgentStatus
          if Status == 'Complete' then
             agent.finalize({ xAction = 'Completion' })
          else
             if HasPendingCancellation then
                agent.cancelStrategy()
             end
          end
       end
    end
    
    
    
    function agent.handleInfo(msg)
       local info = getInfo().full
       msg.reply({
          Action = "Info-Response",
          Data = json.encode(info),
       })
    end
    
    function agent.handleSetStrategy(msg)
       Strat.config(msg)
       Status = "AwaitingDeposit"
       ao.send({
          Target = msg.From,
          Action = "Set-Strategy-Confirmation",
       })
    end
    
    
    
    function agent.isAmmUpdate(msg)
       return msg.Tags.Action == 'Dexi-Swap-Params-Change-Notification' and msg.From == ProcessCfg.Dexi
    end
    
    function agent.isCronTick(msg)
    
       return msg.Tags["Action"] == 'Cron-Tick' and msg.Cron
    end
    
    function agent.isCronTickConfirmation(msg)
       return msg.Tags["Action"] == 'Confirm-Cron-Tick' and msg.From == ao.id
    end
    
    function agent.handleAmmUpdate(msg)
       LatestReserveUpdate = msg
       if TriggerType == 'Swap' then
          agent._handleAmmUpdate(msg)
       end
    end
    
    function agent.handleCronTick(msg)
       if TriggerType == 'Cron' then
          ao.send({ Target = ao.id, Action = 'Confirm-Cron-Tick', Data = json.encode(msg) })
       end
    end
    
    function agent.handleCronTickConfirmation(msg)
       if TriggerType == 'Cron' then
          agent._handleAmmUpdate(LatestReserveUpdate)
       end
    end
    
    
    
    
    function agent.isSusbcriptionConfirmation(msg)
       return msg.Tags.Action == 'Reserve-Change-Subscription-Success' and
       (msg.From == Owner or msg.From == ProcessCfg.Dexi)
    end
    
    function agent.handleSubscriptionConfirmation(msg)
       if Status == 'EmergencyExited' or Status == 'Canceled' then
          unsubscribe()
          return
       end
    
       Status = "Ready"
    
    
    
    
    
    
    
       if msg.Data then
          agent.handleAmmUpdate(msg)
          if TriggerType == 'Cron' then
    
             ao.send({ Target = ao.id, Action = 'Confirm-Cron-Tick', Data = json.encode({ ['isInitCronTick'] = true }) })
          end
       end
    end
    
    
    
    function agent.isTopUpCreditNotice(msg)
       return msg.Tags.Action == 'Credit-Notice' and msg.From == ProcessCfg.TokenFrom and msg.Tags.Sender == ProcessCfg.OrderOwner
    end
    
    function agent.handleTopUpCreditNotice(msg)
       local quantity = msg.Tags.Quantity
    
       if Status ~= "AwaitingDeposit" then
          agent.refundCredit(msg.Tags.Sender, quantity, "Agent is not in the 'AwaitingDeposit' state")
          return
       end
    
       if quantity ~= tostring(ProcessCfg.Input) then
          agent.refundCredit(msg.Tags.Sender, quantity, "Amount does not match the limit order input")
          return
       end
    
       Strat.initialize()
       Status = "AwaitingSubscription"
    
       ao.send({
          Target = Owner,
          Action = "Confirm-Top-Up",
       })
    end
    
    
    
    function agent.isCancellation(msg)
       return msg.Tags.Action == 'Cancel-Order' and msg.From == ProcessCfg.OrderOwner
    end
    
    function agent.handleCancellation(msg)
       agent.cancelStrategy()
    end
    
    
    
    function agent.isExpirationCheck(msg)
       return msg.Tags.Action == "Check-Expiry" and msg.From == ProcessCfg.OrderOwner
    end
    
    function agent.handleExpirationCheck(msg)
       if ProcessCfg.ExpiresAt >= tonumber(msg.Timestamp) then
          return
       end
    
       local shouldNot = Status == "Swapping" or
       Status == "Expired" or
       Status == "EmergencyExited" or
       Status == "Canceled" or
       Status == "Complete"
       if shouldNot then
          msg.reply({
             Action = "Expiry-Check-Error",
             Error = "Cannot check & apply expiry in this state: " .. Status,
          })
          return
       end
    
       local should = Status == "Ready" or
       Status == "AwaitingStrategyConfiguration" or
       Status == "AwaitingSubscription" or
       Status == "AwaitingDeposit"
       if should then
          agent.completeAsExpired()
          return
       end
    
       error("Missed Status value in handleExpirationCheck() case check : " .. Status)
    end
    
    
    
    function agent.isEmergencyWithdrawal(msg)
       return msg.Tags.Action == "Emergency-Withdrawal" and msg.From == ProcessCfg.OrderOwner
    end
    
    function agent.handleEmergencyWithdrawal(msg)
       if not msg.Tags["Token-From-Quantity"] or not msg.Tags["Token-To-Quantity"] then
          agent.sendOrderOwnerFunds(
          "Emergency-Withdrawal")
    
       else
          agent.sendOrderOwnerFunds(
          "Emergency-Withdrawal",
          {
             Input = bint(msg.Tags["Token-From-Quantity"]),
             Output = bint(msg.Tags["Token-To-Quantity"]),
          })
    
       end
    
       Status = 'EmergencyExited'
    
       agent.finalize({
          xAction = 'Emergency-Withdrawal',
          skipFundsTransfer = true,
       })
    end
    
    return agent
    end
    end
    
    do
    local _ENV = _ENV
    package.preload[ "agent.amm-calc" ] = function( ... ) local arg = _G.arg;
    local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local math = _tl_compat and _tl_compat.math or math; require("agent.globals")
    
    local bint = require("utils.tl-bint")(256)
    
    local mod = {}
    
    
    
    
    
    function mod.div_round_up(x, y)
       local quot, rem = bint.tdivmod(x, y)
       if not rem:iszero() and (bint.ispos(x) == bint.ispos(y)) then
          quot:_inc()
       end
       return quot
    end
    
    
    
    
    
    
    
    
    function mod.getOutput(
       inAmount,
       reservesIn,
       reservesOut,
       totalFee)
    
    
       local ammCalcPrecision = 100
       local amountAfterFees = bint.udiv(
       inAmount * bint(math.floor((100 - totalFee) * ammCalcPrecision)),
       bint(100 * ammCalcPrecision))
    
    
       local K = reservesIn * reservesOut
       return reservesOut - mod.div_round_up(K, (reservesIn + amountAfterFees))
    end
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    function mod.getSwapThreshold(resOut, pricePrecisionFactor, resIn, price, fee)
       local ier = (100 - fee) / 100
       local basisPointPrecisionFactor = 10000
       return
    bint.udiv(
       resOut * pricePrecisionFactor, price) -
    
    
       bint.udiv(
       resIn * bint(basisPointPrecisionFactor),
       bint(math.floor(ier * basisPointPrecisionFactor))) -
    
    
       bint(1)
    end
    
    function mod.getPricePrecisionFactor()
       return bint.ipow(bint(10), bint(PricePrecision))
    end
    
    return mod
    end
    end
    
    do
    local _ENV = _ENV
    package.preload[ "agent.globals" ] = function( ... ) local arg = _G.arg;
    require("utils.tl-bint")
    
    
    
    
    
    StatusEnum = {}
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    TProcessCfg = {}
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    FinalizationParams = {}
    
    
    
    
    TSwapsModule = {}
    
    
    
    
    
    
    
    
    
    
    
    Balances = {}
    
    
    
    
    return {}
    end
    end
    
    do
    local _ENV = _ENV
    package.preload[ "agent.strategies.dca-order" ] = function( ... ) local arg = _G.arg;
    local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; require("agent.globals")
    require("agent.strategies.globals")
    
    local bint = require("utils.tl-bint")(256)
    local strategyUtils = require("agent.strategies.strategy-utils")
    local marketOrderFactory = require('agent.strategies.primitives.market-order-action')
    local ammCalc = require("agent.amm-calc")
    
    local function newmodule()
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
       local mod = {
          Initialized = false,
       }
    
    
    
    
       local _TokenFrom
       local _TokenTo
       local _InitialInput
       local _StartTime
       local _EndTime
       local _TickTime
       local _TotalTicks
       local _ExecutedTicks
       local _CapitalPerTick
       local _MarketOrders = {}
    
    
    
    
       function mod.getInfo()
          local mainInfo = strategyUtils.getStrategyInfo(mod)
          return {
             full = mainInfo,
             rootTags = {
                ["Start-Time"] = mainInfo["Start-Time"],
                ["End-Time"] = mainInfo["End-Time"],
                ["Tick-Time"] = mainInfo["Tick-Time"],
                ["Total-Ticks"] = mainInfo["Total-Ticks"],
                ["Executed-Ticks"] = mainInfo["Executed-Ticks"],
                ["Filled-Percentage"] = mainInfo["Filled-Percentage"],
                ["Filled-Price"] = mainInfo["Filled-Price"],
                ["Accumulated-Output"] = mainInfo["Accumulated-Output"],
             },
          }
       end
    
       local function parseCronInterval(interval)
          local parts = {}
          for part in string.gmatch(interval, "([^-]+)") do
             table.insert(parts, part)
          end
          assert(#parts == 2, "Invalid Cron-Interval format")
    
          local value = tonumber(parts[1]) * 1000
          local unit = parts[2]
    
          if unit == "seconds" then
             return bint(value)
          elseif unit == "minutes" then
             return bint(value * 60)
          else
             error("Unsupported Cron-Interval unit: " .. unit)
          end
       end
    
    
    
       function mod.config(msg)
          mod.ConfigMsg = msg
       end
    
    
       local function getCapitalDeployments(totalTicks, input)
          local capitalDeployments = {}
          local capitalPerTick = input // bint(totalTicks)
          local remainingInput = input - (capitalPerTick * bint(totalTicks))
    
          for i = 1, tonumber(totalTicks) do
             local capital = capitalPerTick
             if i == tonumber(totalTicks) then
                capital = capital + remainingInput
             end
             table.insert(capitalDeployments, capital)
          end
    
          return capitalDeployments
       end
    
    
       function mod.initialize()
    
          mod.TokenFrom = ProcessCfg.TokenFrom
          mod.TokenTo = ProcessCfg.TokenTo
          mod.Input = bint(ProcessCfg.Input)
          _StartTime = bint(mod.ConfigMsg.Timestamp)
          _EndTime = bint(mod.ConfigMsg.Tags["End-Time"])
          _TickTime = parseCronInterval(ProcessCfg.CronInterval)
          _TotalTicks = (_EndTime - _StartTime) // _TickTime
          _ExecutedTicks = 0
          _CapitalPerTick = getCapitalDeployments(bint.tonumber(_TotalTicks), mod.Input)
    
          mod.Initialized = true
       end
    
    
    
    
       function mod.handleAmmUpdate(msg)
          local marketOrder = marketOrderFactory.new()
          marketOrder:initialize({
             id = 'market-order-' .. msg.Timestamp,
             tokenFrom = mod.TokenFrom,
             input = _CapitalPerTick[_ExecutedTicks + 1],
          })
    
    
          table.insert(_MarketOrders, marketOrder)
          local orderResult = marketOrder:execute()
    
          local nextAgentStatus
          if marketOrder.IsComplete then
    
             nextAgentStatus = "Ready"
             _ExecutedTicks = _ExecutedTicks + 1
          end
    
          if _ExecutedTicks == bint.tointeger(_TotalTicks) then
             nextAgentStatus = "Complete"
          end
    
          return { swapResult = orderResult, nextAgentStatus = nextAgentStatus }
       end
    
       function mod.getPrimitives()
          return _MarketOrders
       end
    
       local function getExecutionInfo()
          local totalInput = bint(0)
          local totalOutput = bint(0)
    
          for _, order in ipairs(_MarketOrders) do
             if not order.IsComplete then
                break
             end
    
             totalInput = totalInput + order._Input
             totalOutput = totalOutput + order._Output
          end
    
          local fillPrice = bint(-1)
          if totalInput:gt(bint(0)) then
             fillPrice = bint.udiv(totalOutput * ammCalc.getPricePrecisionFactor(), totalInput)
          end
    
          return {
             fillPrice = fillPrice,
             accumulatedOutput = totalOutput,
          }
       end
    
       function mod.getMainInfo()
          local mainInfo = {}
    
    
          mainInfo["Input"] = tostring(mod.Input)
          mainInfo["Token-From"] = mod.TokenFrom
          mainInfo["Token-To"] = mod.TokenTo
          mainInfo["Start-Time"] = tostring(_StartTime)
          mainInfo["End-Time"] = tostring(_EndTime)
          mainInfo["Tick-Time"] = tostring(_TickTime)
          mainInfo["Total-Ticks"] = tostring(_TotalTicks)
          mainInfo["Executed-Ticks"] = tostring(_ExecutedTicks)
    
          local filledPercentage = math.floor(bint.tointeger(_ExecutedTicks) / bint.tointeger(_TotalTicks) * 100)
          mainInfo["Filled-Percentage"] = tostring(filledPercentage)
    
          local executionInfo = getExecutionInfo()
          if executionInfo.fillPrice:gt(bint(0)) then
             mainInfo["Filled-Price"] = tostring(executionInfo.fillPrice)
          else
             mainInfo["Filled-Price"] = 'n/A'
          end
          mainInfo["Accumulated-Output"] = tostring(executionInfo.accumulatedOutput)
    
          return mainInfo
       end
    
       return mod
    
    end
    
    return newmodule
    end
    end
    
    do
    local _ENV = _ENV
    package.preload[ "agent.strategies.globals" ] = function( ... ) local arg = _G.arg;
    require("agent.globals")
    require("utils.tl-bint")
    
    SwapResultEnum = {}
    
    
    
    
    
    
    AmmUpdateResult = {}
    
    
    
    
    StrategyInfo = {}
    
    
    
    
    Strategy = {}
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    TStrategyUtils = {}
    
    
    
    
    
    
    
    
    
    
    
    PersistedSwap = {}
    
    
    
    
    ActionPrimitive = {}
    
    
    
    
    StrategyPrimitive = {}
    
    
    
    
    
    
    StopLimitType = {}
    end
    end
    
    do
    local _ENV = _ENV
    package.preload[ "agent.strategies.limit-order" ] = function( ... ) local arg = _G.arg;
    local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local table = _tl_compat and _tl_compat.table or table; require("agent.globals")
    require("agent.strategies.globals")
    
    local bint = require("utils.tl-bint")(256)
    local strategyUtils = require("agent.strategies.strategy-utils")
    
    local limitOrderFactory = require('agent.strategies.primitives.limit-order-action')
    local marketOrderFactory = require('agent.strategies.primitives.market-order-action')
    local triggerFactory = require('agent.strategies.primitives.price-trigger')
    
    
    local function newmodule()
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
       local mod = {
          Initialized = false,
       }
    
       local _MainLimitOrder
       local _StopTrigger
       local _StopMarketOrderAction
       local _StopLimitOrderAction
    
    
    
       local _MinOutput
       local _HasStopLoss = false
       local _StopPrice
       local _IsStopLimit = false
       local _StopLimitType
       local _StopLimitDifference
       local _StopLimitMinOutput
    
       function mod.config(msg)
    
          mod.ConfigMsg = msg
       end
    
    
    
       function mod.getInfo()
          local info = strategyUtils.getStrategyInfo(mod)
          local strategyPrimitivesInfo = info.Primitives
          if info["Strategy-Status"] == "NOT_INITIALIZED" then
             return {
                full = info,
                rootTags = {
                   ["Min-Output"] = mod.ConfigMsg.Tags["Min-Output"],
                   ["Stop-Price"] = mod.ConfigMsg.Tags["Stop-Price"],
                   ["Is-Stop-Limit"] = mod.ConfigMsg.Tags["Is-Stop-Limit"],
                   ["Stop-Limit-Type"] = mod.ConfigMsg.Tags["Stop-Limit-Type"],
                   ["Stop-Limit-Difference"] = mod.ConfigMsg.Tags["Stop-Limit-Difference"],
                   ["Stop-Limit-Min-Output"] = mod.ConfigMsg.Tags["Stop-Limit-Min-Output"],
                },
             }
          end
    
          local mainLimitOrderInfo = strategyPrimitivesInfo['main-limit-order'] or {}
          local stopTriggerInfo = strategyPrimitivesInfo['stop-trigger'] or {}
          return {
             full = info,
             rootTags = {
                ["Min-Output"] = mod.ConfigMsg.Tags["Min-Output"],
    
                ["Filled-Percentage"] = mainLimitOrderInfo["Filled-Percentage"],
                ["Filled-Price"] = mainLimitOrderInfo['Filled-Price'],
    
                ["Stop-Price"] = mod.ConfigMsg.Tags["Stop-Price"],
                ["Is-Stop-Limit"] = mod.ConfigMsg.Tags["Is-Stop-Limit"],
                ["Stop-Limit-Type"] = mod.ConfigMsg.Tags["Stop-Limit-Type"],
                ["Stop-Limit-Difference"] = mod.ConfigMsg.Tags["Stop-Limit-Difference"],
                ["Stop-Limit-Min-Output"] = mod.ConfigMsg.Tags["Stop-Limit-Min-Output"],
    
                ["Was-Hit"] = stopTriggerInfo["Was-Hit"],
             },
          }
       end
    
    
    
       function mod.initialize()
    
          mod.TokenFrom = ProcessCfg.TokenFrom
          mod.TokenTo = ProcessCfg.TokenTo
          mod.Input = bint(ProcessCfg.Input)
    
    
    
          _MinOutput = bint(mod.ConfigMsg.Tags["Min-Output"])
    
    
          _MainLimitOrder = limitOrderFactory.new()
          _MainLimitOrder:initialize({
             id = 'main-limit-order',
             tokenFrom = mod.TokenFrom,
             tokenTo = mod.TokenTo,
             input = mod.Input,
             minOutput = _MinOutput,
          })
    
          local stopPrice = mod.ConfigMsg.Tags["Stop-Price"]
          if stopPrice then
             _StopPrice = bint(stopPrice)
             _HasStopLoss = true
             _StopTrigger = triggerFactory.new()
             _StopTrigger:initialize({
                id = 'stop-trigger',
    
                tokenFrom = mod.TokenTo,
                denomTokenFrom = strategyUtils.getTokenDenomination(mod.TokenTo),
                tokenTo = mod.TokenFrom,
                denomTokenTo = strategyUtils.getTokenDenomination(mod.TokenFrom),
                stopPrice = strategyUtils.invertStopPrice(_StopPrice),
                triggerDirection = 'Stop',
             })
    
    
    
             _IsStopLimit = mod.ConfigMsg.Tags["Is-Stop-Limit"] == "true"
             if _IsStopLimit then
                _StopLimitType = mod.ConfigMsg.Tags["Stop-Limit-Type"]
    
                if _StopLimitType == 'absolute' then
                   _StopLimitMinOutput = bint(mod.ConfigMsg.Tags["Stop-Limit-Min-Output"])
                else
                   _StopLimitDifference = bint(mod.ConfigMsg.Tags["Stop-Limit-Difference"])
                end
             end
          end
    
          mod.Initialized = true
       end
    
       local function placeOrderOnStopHit(inputQty)
          if not _IsStopLimit then
    
             _StopMarketOrderAction = marketOrderFactory.new()
             _StopMarketOrderAction:initialize({
                id = 'stop-market-order',
    
                tokenFrom = mod.TokenTo,
                input = inputQty,
             })
          else
    
             _StopLimitOrderAction = limitOrderFactory.new()
             local minOutput = _StopLimitType == 'absolute' and
             _StopLimitMinOutput or
             strategyUtils.getMinOutputForRelativeStopLimit(
             _StopLimitDifference,
             _StopPrice,
             mod.Input)
    
             _StopLimitOrderAction:initialize({
                id = 'stop-limit-order',
    
                tokenFrom = mod.TokenTo,
                tokenTo = mod.TokenFrom,
                input = inputQty,
                minOutput = minOutput,
             })
          end
       end
    
    
    
    
    
    
    
    
    
       local _Int = {}
    
    
    
    
       function mod.handleAmmUpdate(msg)
          if not _HasStopLoss then
             return _Int.execMainOrder(msg, false)
          else
             if _StopTrigger.WasHit then
    
                return _Int.execStopOrder()
             end
    
    
             _StopTrigger:handleAmmUpdate(msg)
    
             if _StopTrigger.WasHit then
                local tokenToBalance = strategyUtils.getActionTotalSwapOutput(_MainLimitOrder)
    
                if bint.ispos(tokenToBalance) then
    
                   local swapQty = strategyUtils.getActionTotalSwapOutput(
                   _MainLimitOrder)
    
                   placeOrderOnStopHit(swapQty)
                   return _Int.execStopOrder(msg)
                end
    
                return { swapResult = "NoSwap", nextAgentStatus = "Complete" }
             end
    
    
             local isMainLimitActive = not _MainLimitOrder.IsComplete
             if isMainLimitActive then
    
                return _Int.execMainOrder(msg, true)
             end
    
             return { swapResult = "NoSwap", nextAgentStatus = "Ready" }
    
          end
       end
    
    
       function _Int.execMainOrder(ammUpdateMsg, withStopLoss)
          local swapResult = _MainLimitOrder:handleAmmUpdate(ammUpdateMsg)
          local status
          if withStopLoss then
             status = "Ready"
          end
          status = _MainLimitOrder.IsComplete and "Complete" or "Ready"
          return { swapResult = swapResult, nextAgentStatus = status }
       end
    
       function _Int.execStopOrder(ammUpdateMsg)
          local action = _IsStopLimit and _StopLimitOrderAction or _StopMarketOrderAction
          local swapResult = action:handleAmmUpdate(ammUpdateMsg)
    
          local status = action.IsComplete and "Complete" or "Ready"
          return { swapResult = swapResult, nextAgentStatus = status }
       end
    
    
    
    
       function mod.getPrimitives()
          local primitives = {}
          table.insert(primitives, _MainLimitOrder)
          if _StopTrigger then
             table.insert(primitives, _StopTrigger)
          end
          if _StopMarketOrderAction then
             table.insert(primitives, _StopMarketOrderAction)
          end
          if _StopLimitOrderAction then
             table.insert(primitives, _StopLimitOrderAction)
          end
          return primitives
       end
    
       function mod.getMainInfo()
          local mainInfo = {}
    
          mainInfo["Min-Output"] = tostring(_MinOutput)
          if _HasStopLoss then
             mainInfo["Stop-Price"] = tostring(_StopPrice)
             mainInfo["Is-Stop-Limit"] = tostring(_IsStopLimit)
             mainInfo["Stop-Limit-Type"] = _StopLimitType
             mainInfo["Stop-Limit-Difference"] = _StopLimitDifference and tostring(_StopLimitDifference)
             mainInfo["Stop-Limit-Min-Output"] = _StopLimitMinOutput and tostring(_StopLimitMinOutput)
          end
    
          return mainInfo
       end
    
    
       return mod
    
    end
    
    return newmodule
    end
    end
    
    do
    local _ENV = _ENV
    package.preload[ "agent.strategies.primitives.limit-order-action" ] = function( ... ) local arg = _G.arg;
    local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local table = _tl_compat and _tl_compat.table or table; require("agent.globals")
    require("agent.strategies.globals")
    
    local ammCalc = require("agent.amm-calc")
    local bint = require("utils.tl-bint")(256)
    
    local strategyUtils = require("agent.strategies.strategy-utils")
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    LimitOrderAction = {}
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    local createInitial = function()
       return {
          Id = '',
          IsInitialized = false,
          IsComplete = false,
          Swaps = {},
    
          _TokenFrom = nil,
          _TokenTo = nil,
          _InitialInput = nil,
          _MinOutput = nil,
    
          _Input = nil,
          _Output = nil,
       }
    end
    
    local LimitOrder = createInitial()
    
    
    function LimitOrder:initialize(cfg)
       self.Id = cfg.id
       self._TokenFrom = cfg.tokenFrom
       self._TokenTo = cfg.tokenTo
       self._InitialInput = cfg.input
       self._MinOutput = cfg.minOutput
    
       self._Input = self._InitialInput
       self._Output = bint(0)
       self.IsInitialized = true
    end
    
    
    
    function LimitOrder:getInfo()
       return {
          ["Is-Initialized"] = tostring(self.IsInitialized),
          ["Is-Complete"] = tostring(self.IsComplete),
          ["Min-Output"] = tostring(self._MinOutput),
          ["Price"] = tostring(self:_getPrice()),
          ["Price-Precision"] = tostring(PricePrecision),
          ["Filled-Percentage"] = tostring(self:_getFilledPercentage()),
          ["Filled-Price"] = tostring(self:_getFillPrice()),
          ["Available-Input"] = tostring(self._Input),
          ["Accumulated-Output"] = tostring(self._Output),
          ["Token-From"] = self._TokenFrom,
          ["Token-To"] = self._TokenTo,
          ["Swaps"] = self.Swaps,
       }
    end
    
    
    
    function LimitOrder:recordSwap(msg)
       local inputQty = bint(msg.Tags["From-Quantity"])
       local outputQty = bint(msg.Tags["To-Quantity"])
    
       self._Input = self._Input - inputQty
       self._Output = self._Output + outputQty
    
       table.insert(self.Swaps, strategyUtils.createPersistableSwap(msg))
    end
    
    function LimitOrder.getSwapsModule()
       return SwapsModule
    end
    
    function LimitOrder:handleAmmUpdate(msg)
       assert(not self.IsComplete, "Limit Order Action " .. self.Id .. " : handleAmmUpdate() called after action is complete")
    
    
       assert(bint(0) ~= self._Input, "Limit Order Action " .. self.Id .. " : No input token quantity available")
    
       local price = self:_getPrice()
    
       assert(bint.isbint(price), "Limit Order Action " .. self.Id .. " : Cannot derive price")
       price = price
    
       local resIn, resOut, fee = strategyUtils.getSwapParamsOnAmmUpdate(msg, self._TokenFrom, self._TokenTo)
    
    
       local threshold = ammCalc.getSwapThreshold(resOut, ammCalc.getPricePrecisionFactor(), resIn, price, fee)
    
       print('Limit Order exec')
       print('price : ' .. tostring(price))
       print('threshold : ' .. tostring(threshold))
    
       if bint.ispos(threshold) then
    
          local swapInput = bint.ult(self._Input, threshold) and self._Input or threshold
          local expectedOutput = ammCalc.getOutput(swapInput, resIn, resOut, fee)
          if expectedOutput ~= bint(0) then
             local success, swapConclusion = SwapsModule.swapForMinOutputWithQty(
             self._TokenFrom,
             swapInput,
             expectedOutput)
    
             if success then
                self:recordSwap(swapConclusion)
    
                assert(bint.ispos(self._Input) or self._Input == bint(0), self.Id .. "handle swap confirmation: self._Input cannot become negative")
                self.IsComplete = self._Input == bint(0)
                return "SuccessfulSwap"
             else
                return "FailedSwap"
             end
          end
       end
    
       return "NoSwap"
    end
    
    
    
    
    
    
    
    
    
    
    function LimitOrder:_getPrice()
       local canCalc = self._InitialInput and
       self._MinOutput
       if not canCalc then return "n/A" end
       return bint.udiv(self._MinOutput * ammCalc.getPricePrecisionFactor(), self._InitialInput)
    end
    
    function LimitOrder:_getFillPrice()
       local hasValues = self._InitialInput and self._Input
       if not hasValues then return 'n/A' end
       local consumedInput = self._InitialInput - self._Input
       if consumedInput == bint(0) then return 'n/A' end
       return bint.udiv(self._Output * ammCalc.getPricePrecisionFactor(), consumedInput)
    end
    
    function LimitOrder:_getFilledPercentage()
       local canCalc = self._InitialInput and
       self._InitialInput ~= bint(0) and
       self.Swaps
    
       if not canCalc then return 'n/A' end
    
       local usedInput = bint(0)
       for _, v in ipairs(self.Swaps) do
          usedInput = usedInput + bint(v["From-Quantity"])
       end
    
       local precision = bint(10000)
       local filled = bint.udiv(usedInput * precision, self._InitialInput)
       return bint.tonumber(filled) / 100
    end
    
    local LimitOrderFactory = {}
    
    function LimitOrderFactory.new()
       local self = setmetatable({}, { __index = LimitOrder })
       return self
    end
    
    return LimitOrderFactory
    end
    end
    
    do
    local _ENV = _ENV
    package.preload[ "agent.strategies.primitives.market-order-action" ] = function( ... ) local arg = _G.arg;
    local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local table = _tl_compat and _tl_compat.table or table; require("agent.globals")
    require("agent.strategies.globals")
    
    local ammCalc = require("agent.amm-calc")
    local bint = require("utils.tl-bint")(256)
    
    local strategyUtils = require("agent.strategies.strategy-utils")
    
    
    
    
    
    
    
    
    
    MarketOrderAction = {}
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    local createInitial = function()
       return {
          Id = '',
          IsInitialized = false,
          IsComplete = false,
          Swaps = {},
    
          _TokenFrom = nil,
    
          _Input = nil,
          _Output = nil,
       }
    end
    
    local MarketOrder = createInitial()
    
    
    function MarketOrder:initialize(cfg)
       self.Id = cfg.id
       self._TokenFrom = cfg.tokenFrom
       self._Input = cfg.input
       self.IsInitialized = true
    end
    
    
    
    function MarketOrder:getInfo()
       return {
          ["Token-From"] = self._TokenFrom,
          ["Is-Initialized"] = tostring(self.IsInitialized),
          ["Is-Complete"] = tostring(self.IsComplete),
          ["Filled-Price"] = tostring(self:_getFillPrice()),
          ["Accumulated-Output"] = tostring(self._Output),
          ["Available-Input"] = tostring(self._Input),
          ["Swaps"] = self.Swaps,
       }
    end
    
    
    
    function MarketOrder:recordSwap(msg)
       local outputQty = bint(msg.Tags["To-Quantity"])
       self._Output = outputQty
    
       table.insert(self.Swaps, strategyUtils.createPersistableSwap(msg))
    end
    
    function MarketOrder:execute()
       assert(not self.IsComplete, "Market Order Action " .. self.Id .. " : handleAmmUpdate() called after primitive is complete")
    
       assert(bint.ult(bint(0), self._Input), "Market Order Action " .. self.Id .. " : No input token quantity available")
    
       local swapInput = self._Input
       local success, swapConclusion = SwapsModule.swapForMinOutputWithQty(
       self._TokenFrom,
       swapInput,
       bint(1))
    
    
       if success then
          self:recordSwap(swapConclusion)
          self.IsComplete = true
          return "SuccessfulSwap"
       else
          return "FailedSwap"
       end
    
       return "NoSwap"
    end
    
    
    
    function MarketOrder:_getFillPrice()
       if not self._Input or not self._Output or not self.IsComplete then return 'n/A' end
       return bint.udiv(self._Output * ammCalc.getPricePrecisionFactor(), self._Input)
    end
    
    local MarketOrderFactory = {}
    
    function MarketOrderFactory.new()
       local self = setmetatable(createInitial(), { __index = MarketOrder })
       return self
    end
    
    return MarketOrderFactory
    end
    end
    
    do
    local _ENV = _ENV
    package.preload[ "agent.strategies.primitives.price-trigger" ] = function( ... ) local arg = _G.arg;
    local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; require("agent.globals")
    require("agent.strategies.globals")
    
    local ammCalc = require("agent.amm-calc")
    local bint = require("utils.tl-bint")(256)
    
    local strategyUtils = require("agent.strategies.strategy-utils")
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    PriceTrigger = {}
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    local createInitial = function()
       return {
          Id = '',
          IsInitialized = false,
          WasHit = false,
    
          _TokenFrom = nil,
          _TokenTo = nil,
          _DenomTokenFrom = nil,
          _DenomTokenTo = nil,
          _TriggerPrice = nil,
          _TriggerDirection = nil,
          _LastPriceReceived = nil,
          _IsTrailing = false,
          _TrailingDifference = nil,
       }
    end
    
    local Trigger = createInitial()
    
    
    
    
    
    
    function Trigger:initialize(cfg)
       self.Id = cfg.id
       self._TokenFrom = cfg.tokenFrom
       self._TokenTo = cfg.tokenTo
       self._DenomTokenFrom = cfg.denomTokenFrom
       self._DenomTokenTo = cfg.denomTokenTo
       self._TriggerPrice = cfg.stopPrice
       self._TriggerDirection = cfg.triggerDirection
       self._IsTrailing = cfg.isTrailing
       self._TrailingDifference = cfg.trailingDifference
       self.IsInitialized = true
    
       if self._IsTrailing then
          assert(self._TriggerDirection == "Stop", "Internal Error: Trailing is only supported for Stop triggers")
       end
    end
    
    
    
    function Trigger:getInfo()
       local payload = {
          ["Token-From"] = self._TokenFrom,
          ["Token-To"] = self._TokenTo,
          ["Denom-Token-From"] = tostring(self._DenomTokenFrom),
          ["Denom-Token-To"] = tostring(self._DenomTokenTo),
          ["Is-Initialized"] = tostring(self.IsInitialized),
          ["Was-Hit"] = tostring(self.WasHit),
          ["Stop-Price"] = tostring(self._TriggerPrice),
          ["Price-Precision"] = tostring(PricePrecision),
          ["Last-Price-Received"] = tostring(self._LastPriceReceived),
          ["Trigger-Direction"] = tostring(self._TriggerDirection),
          ["Is-Trailing"] = tostring(self._IsTrailing),
          ["Trailing-Difference"] = self._TrailingDifference and tostring(self._TrailingDifference) or nil,
       }
       return payload
    end
    
    
    
    function Trigger:handleAmmUpdate(msg)
       assert(not self.WasHit, "Strategy Trigger: handleAmmUpdate() called after trigger was hit")
    
       local resIn, resOut = strategyUtils.getSwapParamsOnAmmUpdate(msg, self._TokenFrom, self._TokenTo)
       local price = self._getPriceForTriggerCheck(resIn, resOut, self._DenomTokenFrom, self._DenomTokenTo)
       local formerPrice = self._LastPriceReceived
       self._LastPriceReceived = price
    
    
    
    
    
    
    
    
       local shouldUpdateAsTrailing = self._IsTrailing and (formerPrice == nil or bint.ult(formerPrice, price))
       if shouldUpdateAsTrailing then
          self:_updateTrailingStopPrice(price)
          return
       end
    
    
       local isStopTriggered = self._TriggerDirection == "Stop" and bint.ule(price, self._TriggerPrice)
       local isTakeProfitTriggered = self._TriggerDirection == "TakeProfit" and bint.ule(self._TriggerPrice, price)
       if isStopTriggered or isTakeProfitTriggered then
          self.WasHit = true
       end
    end
    
    function Trigger._getPriceForTriggerCheck(resIn, resOut, denomIn, denomOut)
       local outDenomFactor = bint.ipow(bint(10), bint(denomOut))
       local inDenomFactor = bint.ipow(bint(10), bint(denomIn))
       return bint.udiv(resOut * inDenomFactor * ammCalc.getPricePrecisionFactor(), resIn * outDenomFactor)
    end
    
    function Trigger:_updateTrailingStopPrice(currentPrice)
       self._TriggerPrice = bint.udiv(
       currentPrice * (bint(10000) - self._TrailingDifference),
       bint(10000))
    
    end
    
    
    
    local TriggerFactory = {}
    
    function TriggerFactory.new()
       local self = setmetatable(createInitial(), { __index = Trigger })
       return self
    end
    
    return TriggerFactory
    end
    end
    
    do
    local _ENV = _ENV
    package.preload[ "agent.strategies.stop-order" ] = function( ... ) local arg = _G.arg;
    local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local table = _tl_compat and _tl_compat.table or table; require("agent.globals")
    require("agent.strategies.globals")
    
    local bint = require("utils.tl-bint")(256)
    local strategyUtils = require("agent.strategies.strategy-utils")
    
    local limitOrderFactory = require('agent.strategies.primitives.limit-order-action')
    local marketOrderFactory = require('agent.strategies.primitives.market-order-action')
    local triggerFactory = require('agent.strategies.primitives.price-trigger')
    
    local function newmodule()
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
       local mod = {
          Initialized = false,
       }
    
       local _StopTrigger
       local _MarketOrderAction
       local _LimitOrderAction
    
    
    
       local _StopPrice
       local _IsStopLimit = false
       local _StopLimitType
       local _StopLimitDifference
       local _StopLimitMinOutput
       local _IsTrailing = false
       local _TrailingDifference
    
       function mod.config(msg)
    
          mod.ConfigMsg = msg
       end
    
    
    
       function mod.getInfo()
          local info = strategyUtils.getStrategyInfo(mod)
          local strategyPrimitivesInfo = info.Primitives
          if not strategyPrimitivesInfo then
             return {
                full = info,
                rootTags = {
                   ["Stop-Price"] = mod.ConfigMsg.Tags["Stop-Price"],
                   ["Is-Stop-Limit"] = mod.ConfigMsg.Tags["Is-Stop-Limit"],
                   ["Stop-Limit-Type"] = mod.ConfigMsg.Tags["Stop-Limit-Type"],
                   ["Stop-Limit-Difference"] = mod.ConfigMsg.Tags["Stop-Limit-Difference"],
                   ["Stop-Limit-Min-Output"] = mod.ConfigMsg.Tags["Stop-Limit-Min-Output"],
                   ["Is-Trailing"] = mod.ConfigMsg.Tags["Is-Trailing"],
                   ["Trailing-Difference"] = mod.ConfigMsg.Tags["Trailing-Difference"],
                },
             }
          end
          local triggerInfo = strategyPrimitivesInfo['stop-trigger'] or {}
          local placedOrderInfo = strategyPrimitivesInfo[_IsStopLimit and 'stop-limit-order' or 'stop-market-order'] or {}
          return {
             full = info,
             rootTags = {
                ["Is-Stop-Limit"] = mod.ConfigMsg.Tags["Is-Stop-Limit"],
                ["Stop-Limit-Type"] = mod.ConfigMsg.Tags["Stop-Limit-Type"],
                ["Stop-Limit-Difference"] = mod.ConfigMsg.Tags["Stop-Limit-Difference"],
                ["Stop-Limit-Min-Output"] = mod.ConfigMsg.Tags["Stop-Limit-Min-Output"],
                ["Is-Trailing"] = mod.ConfigMsg.Tags["Is-Trailing"],
                ["Trailing-Difference"] = mod.ConfigMsg.Tags["Trailing-Difference"],
    
                ["Stop-Price"] = triggerInfo["Stop-Price"],
                ["Was-Hit"] = triggerInfo["Was-Hit"],
    
    
                ["Filled-Percentage"] = placedOrderInfo["Filled-Percentage"],
                ["Filled-Price"] = placedOrderInfo['Filled-Price'],
                ["Min-Out-Placed-Order"] = placedOrderInfo['Min-Out'],
                ["Output"] = placedOrderInfo["Accumulated-Output"],
             },
          }
       end
    
    
    
       function mod.initialize()
    
          mod.TokenFrom = ProcessCfg.TokenFrom
          mod.TokenTo = ProcessCfg.TokenTo
          mod.Input = bint(ProcessCfg.Input)
    
    
    
          _StopPrice = bint(mod.ConfigMsg.Tags["Stop-Price"])
          _IsTrailing = mod.ConfigMsg.Tags["Is-Trailing"] == "true"
          _TrailingDifference = _IsTrailing and bint(mod.ConfigMsg.Tags["Trailing-Difference"]) or nil
    
    
          _StopTrigger = triggerFactory.new()
          _StopTrigger:initialize({
             id = 'stop-trigger',
             tokenFrom = mod.TokenFrom,
             denomTokenFrom = strategyUtils.getTokenDenomination(mod.TokenFrom),
             tokenTo = mod.TokenTo,
             denomTokenTo = strategyUtils.getTokenDenomination(mod.TokenTo),
             stopPrice = _StopPrice,
             triggerDirection = 'Stop',
             isTrailing = _IsTrailing,
             trailingDifference = _TrailingDifference,
          })
    
    
          _IsStopLimit = mod.ConfigMsg.Tags["Is-Stop-Limit"] == "true"
          if _IsStopLimit then
             _StopLimitType = mod.ConfigMsg.Tags["Stop-Limit-Type"]
    
             if _StopLimitType == 'absolute' then
                _StopLimitMinOutput = bint(mod.ConfigMsg.Tags["Stop-Limit-Min-Output"])
             else
                _StopLimitDifference = bint(mod.ConfigMsg.Tags["Stop-Limit-Difference"])
             end
          end
    
          mod.Initialized = true
       end
    
       local function placeOrderOnStopHit()
          if not _IsStopLimit then
    
             _MarketOrderAction = marketOrderFactory.new()
             _MarketOrderAction:initialize({
                id = 'stop-market-order',
                tokenFrom = mod.TokenFrom,
                input = mod.Input,
             })
          else
    
             _LimitOrderAction = limitOrderFactory.new()
             local minOutput = _StopLimitType == 'absolute' and
             _StopLimitMinOutput or
             strategyUtils.getMinOutputForRelativeStopLimit(
             _StopLimitDifference,
             _StopPrice,
             mod.Input)
    
             _LimitOrderAction:initialize({
                id = 'stop-limit-order',
                tokenFrom = mod.TokenFrom,
                tokenTo = mod.TokenTo,
                input = mod.Input,
                minOutput = minOutput,
             })
          end
       end
    
    
    
    
    
    
    
    
       local _Int = {}
    
    
    
    
       function mod.handleAmmUpdate(msg)
          if _StopTrigger.WasHit then
    
             return _Int.execOrder(msg)
          else
    
             _StopTrigger:handleAmmUpdate(msg)
    
             if _StopTrigger.WasHit then
    
                placeOrderOnStopHit()
                return _Int.execOrder(msg)
             else
    
                return { swapResult = "NoSwap", nextAgentStatus = "Ready" }
             end
          end
       end
    
       function _Int.execOrder(ammUpdateMsg)
          local swapResult
          local status
          if _IsStopLimit then
             swapResult = _LimitOrderAction:handleAmmUpdate(ammUpdateMsg)
    
             status = _LimitOrderAction.IsComplete and "Complete" or "Ready"
          else
             swapResult = _MarketOrderAction:execute()
    
             status = _MarketOrderAction.IsComplete and "Complete" or "Ready"
          end
          return { swapResult = swapResult, nextAgentStatus = status }
       end
    
    
    
       function mod.getPrimitives()
          local primitives = {}
          if _StopTrigger then
             table.insert(primitives, _StopTrigger)
          end
          if _MarketOrderAction then
             table.insert(primitives, _MarketOrderAction)
          end
          if _LimitOrderAction then
             table.insert(primitives, _LimitOrderAction)
          end
    
          return primitives
       end
    
       function mod.getMainInfo()
          local mainInfo = {}
    
          mainInfo["Stop-Price"] = tostring(_StopPrice)
          if _IsStopLimit then
             mainInfo["Is-Stop-Limit"] = "true"
             mainInfo["Stop-Limit-Type"] = _StopLimitType
             mainInfo["Stop-Limit-Difference"] = _StopLimitDifference and tostring(_StopLimitDifference) or nil
             mainInfo["Stop-Limit-Min-Output"] = _StopLimitMinOutput and tostring(_StopLimitMinOutput) or nil
          end
    
          if _IsTrailing then
             mainInfo["Is-Trailing"] = "true"
             mainInfo["Trailing-Difference"] = tostring(_TrailingDifference)
          end
    
          return mainInfo
       end
    
       return mod
    
    end
    
    return newmodule
    end
    end
    
    do
    local _ENV = _ENV
    package.preload[ "agent.strategies.strategy-utils" ] = function( ... ) local arg = _G.arg;
    local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; require("agent.strategies.globals")
    
    local ammCalc = require("agent.amm-calc")
    local bint = require("utils.tl-bint")(256)
    local json = require("json")
    
    local mod = {}
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    mod.getMinOutputForRelativeStopLimit = function(stopLimitDifference, stopPrice, input)
       local pricePrecisionFactor = ammCalc.getPricePrecisionFactor()
    
       local outputAtStopPrice = bint.udiv(stopPrice * input, pricePrecisionFactor)
    
       local cfgDiff = stopLimitDifference
    
    
       local basisPointsFactor = bint(10000)
       local sign = bint.ispos(cfgDiff) and bint(1) or bint(-1)
       local abs = bint.abs(cfgDiff)
       local deviation = bint.udiv(outputAtStopPrice * abs, basisPointsFactor) * sign
    
       return outputAtStopPrice + deviation
    end
    
    mod.getActionTotalSwapOutput = function(primitive)
       local output = bint(0)
       for _, swap in ipairs(primitive.Swaps) do
          output = output + bint(swap["To-Quantity"])
       end
       return output
    end
    
    mod.invertStopPrice = function(price)
       local precisionFactor = ammCalc.getPricePrecisionFactor()
       return bint.udiv(precisionFactor * precisionFactor, price)
    end
    
    mod.getSwapParamsOnAmmUpdate = function(msg, token1, token2)
       local payload = json.decode(msg.Data)
    
       assert(token1 and token2, "getSwapParamsOnAmmUpdate: token1 and token2 required; token1 " .. tostring(token1) .. " token2: " .. tostring(token2))
       local token0 = payload["token0"]
    
       local res1 = bint(payload[token0 == token1 and "reserves0" or "reserves1"])
       local res2 = bint(payload[token0 == token2 and "reserves0" or "reserves1"])
       local feeBps = tonumber(payload["pool_fee_bps"])
    
       assert(feeBps, "Missing Fee in Dexi Notification. Got " .. tostring(payload["Fee-Bps"]))
    
       local fee = feeBps / 100
       return res1, res2, fee
    end
    
    
    
    mod.getStrategyInfo = function(strat)
       if not strat.Initialized then
          local configTags = strat.ConfigMsg.Tags
          return {
             ["Strategy-Status"] = "NOT_INITIALIZED",
             ["Config"] = configTags,
          }
       end
    
       local mainInfo = strat.getMainInfo()
    
    
       local info = mainInfo
    
       local primitivesInfo = {}
    
       for _, item in ipairs(strat.getPrimitives()) do
          local itemInfo = item and item:getInfo()
          local id = item and item.Id
          primitivesInfo[id] = itemInfo
       end
       info["Primitives"] = primitivesInfo
    
       return info
    end
    
    mod.getTokenDenomination = function(token)
       local info = ao.send({
          Target = token,
          Action = "Info",
       }).receive()
    
       return tonumber(info.Tags["Denomination"])
    end
    
    mod.createPersistableSwap = function(msg)
       local msgCopy = json.decode(json.encode(msg))
       msgCopy.Tags = nil
       msgCopy.TagArray = nil
       return msgCopy
    end
    
    return mod
    end
    end
    
    do
    local _ENV = _ENV
    package.preload[ "agent.swaps" ] = function( ... ) local arg = _G.arg;
    local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local os = _tl_compat and _tl_compat.os or os; require("agent.globals")
    require("agent.strategies.globals")
    
    local mod = {}
    
    
    
    local function isSwapConfirmation(msg)
       return msg.From == ProcessCfg.AmmFactory and
       msg.Tags["Relayed-From"] == ProcessCfg.Amm and
       msg.Tags["Relay-To"] == ao.id and
       msg.Tags.Action == 'Order-Confirmation'
    end
    
    
    
    
    
    
    
    local function isSwapRefund(msg)
       return msg.Tags.Action == 'Credit-Notice' and
       msg.Tags.Sender == ProcessCfg.Amm and
       msg.Tags["X-Refunded-Order"] ~= nil
    end
    
    function mod._awaitSwap()
       local response = Receive(function(msg)
          return isSwapConfirmation(msg) or isSwapRefund(msg)
       end)
    
       if isSwapConfirmation(response) then
          return true, response
       else
          return false, response
       end
    end
    
    function mod.swapForMinOutputWithQty(
       inputToken,
       inputQty,
       minOutQty)
    
       Status = "Swapping"
       LastSwapAttemptTimestamp = os.time()
       ao.send({
          Target = inputToken,
          Action = "Transfer",
          Recipient = ProcessCfg.Amm,
          Quantity = tostring(inputQty),
          ["X-Action"] = "Swap",
          ["X-Expected-Min-Output"] = tostring(minOutQty),
       })
    
       return mod._awaitSwap()
    end
    
    return mod
    end
    end
    
    do
    local _ENV = _ENV
    package.preload[ "utils.assertions" ] = function( ... ) local arg = _G.arg;
    local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local math = _tl_compat and _tl_compat.math or math; local pcall = _tl_compat and _tl_compat.pcall or pcall; local string = _tl_compat and _tl_compat.string or string; local bint = require("utils.tl-bint")(256)
    local mod = {}
    
    
    function mod.isTimestamp(val, prependMsg)
       local prepended = prependMsg and (prependMsg .. ": ") or ""
    
       local asNum = tonumber(val)
       assert(asNum and asNum > 0 and math.floor(asNum) == asNum, prepended .. "Not a timestamp")
       return true
    end
    
    
    
    
    
    function mod.isBintRaw(val)
       local success, result = pcall(
       function()
    
          if type(val) ~= "number" and type(val) ~= "string" and not bint.isbint(val) then
             return false
          end
    
    
          if type(val) == "number" and (val ~= val or val % 1 ~= 0) then
             return false
          end
    
          return true
       end)
    
    
       return success and result
    end
    
    
    
    
    
    function mod.isTokenQuantity(qty, prependMsg)
       local prepended = prependMsg and (prependMsg .. ": ") or ""
    
       assert(not (type(qty) == "nil"), prepended .. "No quantity provided")
       assert(not (type(qty) == "number" and qty < 0), prepended .. "Negative quantity")
       assert(not (type(qty) == "string" and string.sub(qty, 1, 1) == "-"), prepended .. "Negative quantity")
       assert(mod.isBintRaw(qty), prepended .. "Not a raw bint")
    
       return true
    end
    
    
    function mod.isStopLimitPercentage(val, prependMsg)
       local prepended = prependMsg and (prependMsg .. ": ") or ""
    
       local valNum = tonumber(val)
       assert(type(valNum) == "number", prepended .. "Not parsable to a number")
       assert(math.floor(valNum) == valNum, prepended .. "Not an integer")
       assert(math.abs(valNum) < 10000, prepended .. "The number is >= 10000 or <= -10000")
    
       return true
    end
    
    
    
    
    function mod.isAddress(addr, prependMsg)
       local prepended = prependMsg and (prependMsg .. ": ") or ""
    
       assert(type(addr) == "string", prepended .. "Invalid type for Arweave address (must be string)")
       assert(addr:len() == 43, prepended .. "Invalid length for Arweave address")
       assert(addr:match("[A-z0-9_-]+"), prepended .. "Invalid characters in Arweave address")
       return true
    end
    
    function mod.isAgentType(agentType)
       assert(type(agentType) == "string", "Invalid type for Agent-Type (must be string)")
       assert(agentType == "limit-order" or agentType == "dca-order" or agentType == "stop-order", "Invalid Agent-Type")
       return true
    end
    
    return mod
    end
    end
    
    do
    local _ENV = _ENV
    package.preload[ "utils.tl-bint" ] = function( ... ) local arg = _G.arg;
    local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local debug = _tl_compat and _tl_compat.debug or debug; local math = _tl_compat and _tl_compat.math or math; local _tl_math_maxinteger = math.maxinteger or math.pow(2, 53); local _tl_math_mininteger = math.mininteger or -math.pow(2, 53) - 1; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local _tl_table_unpack = unpack or table.unpack; BigInteger = {}
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    local function luainteger_bitsize()
       local n = -1
       local i = 0
       repeat
          n, i = n >> 16, i + 16
       until n == 0
       return i
    end
    
    local math_type = math.type
    local math_floor = math.floor
    local math_abs = math.abs
    local math_ceil = math.ceil
    local math_modf = math.modf
    local math_mininteger = _tl_math_mininteger
    local math_maxinteger = _tl_math_maxinteger
    local math_max = math.max
    local math_min = math.min
    local string_format = string.format
    local table_insert = table.insert
    local table_concat = table.concat
    local table_unpack = _tl_table_unpack
    
    local memo = {}
    
    
    
    
    
    
    
    
    local function newmodule(bits, wordbits)
    
       local intbits = luainteger_bitsize()
       bits = bits or 256
       wordbits = wordbits or (intbits // 2)
    
    
       local memoindex = bits * 64 + wordbits
       if memo[memoindex] then
          return memo[memoindex]
       end
    
    
       assert(bits % wordbits == 0, 'bitsize is not multiple of word bitsize')
       assert(2 * wordbits <= intbits, 'word bitsize must be half of the lua integer bitsize')
       assert(bits >= 64, 'bitsize must be >= 64')
       assert(wordbits >= 8, 'wordbits must be at least 8')
       assert(bits % 8 == 0, 'bitsize must be multiple of 8')
    
    
       local bint = {}
       bint.__index = bint
    
    
       bint.bits = bits
    
    
       local BINT_BITS = bits
       local BINT_BYTES = bits // 8
       local BINT_WORDBITS = wordbits
       local BINT_SIZE = BINT_BITS // BINT_WORDBITS
       local BINT_WORDMAX = (1 << BINT_WORDBITS) - 1
       local BINT_WORDMSB = (1 << (BINT_WORDBITS - 1))
       local BINT_LEPACKFMT = '<' .. ('I' .. (wordbits // 8)):rep(BINT_SIZE)
       local BINT_MATHMININTEGER
       local BINT_MATHMAXINTEGER
       local BINT_MININTEGER
    
    
       function bint.zero()
          local x = setmetatable({}, bint)
          for i = 1, BINT_SIZE do
             x[i] = 0
          end
          return x
       end
       local bint_zero = bint.zero
    
    
       function bint.one()
          local x = setmetatable({}, bint)
          x[1] = 1
          for i = 2, BINT_SIZE do
             x[i] = 0
          end
          return x
       end
       local bint_one = bint.one
    
    
       local function tointeger(x)
          x = tonumber(x)
          local ty = math_type(x)
          if ty == 'float' then
             local floorx = math_floor(x)
             if floorx == x then
                x = floorx
                ty = math_type(x)
             end
          end
          if ty == 'integer' then
             return x
          end
       end
    
    
    
    
    
    
       function bint.fromuinteger(x)
          x = tointeger(x)
          if x then
             if x == 1 then
                return bint_one()
             elseif x == 0 then
                return bint_zero()
             end
             local n = setmetatable({}, bint)
             for i = 1, BINT_SIZE do
                n[i] = x & BINT_WORDMAX
                x = x >> BINT_WORDBITS
             end
             return n
          end
       end
       local bint_fromuinteger = bint.fromuinteger
    
    
    
    
    
       function bint.frominteger(x)
          x = tointeger(x)
          if x then
             if x == 1 then
                return bint_one()
             elseif x == 0 then
                return bint_zero()
             end
             local neg = false
             if x < 0 then
                x = math_abs(x)
                neg = true
             end
             local n = setmetatable({}, bint)
             for i = 1, BINT_SIZE do
                n[i] = x & BINT_WORDMAX
                x = x >> BINT_WORDBITS
             end
             if neg then
                n:_unm()
             end
             return n
          end
       end
       local bint_frominteger = bint.frominteger
    
    
       local basesteps = {}
    
    
       local function getbasestep(base)
          local step = basesteps[base]
          if step then
             return step
          end
          step = 0
          local dmax = 1
          local limit = math_maxinteger // base
          repeat
             step = step + 1
             dmax = dmax * base
          until dmax >= limit
          basesteps[base] = step
          return step
       end
    
    
       local function ipow(y, x, n)
          if n == 1 then
             return y * x
          elseif n & 1 == 0 then
             return ipow(y, x * x, n // 2)
          end
          return ipow(x * y, x * x, (n - 1) // 2)
       end
    
    
    
    
    
    
       function bint.isbint(x)
    
    
    
    
          local isTable = type(x) == 'table'
          local mt = getmetatable(x)
    
          local isBintish = mt and
          mt.isbint and
          mt.tobint and
          mt.zero and
          mt.iszero and
          mt.frombase and
          mt.tobase and
          mt.isneg and
          mt.ispos and
          true
    
          return isTable and isBintish
       end
    
    
       local function bint_assert_convert(x)
          if not bint.isbint(x) then
             print(debug.traceback())
             assert(bint.isbint(x), 'bint_assert_convert: expected BigInteger, got ' .. type(x) .. ' value ' .. tostring(x))
          end
          return x
       end
    
    
       local function bint_assert_convert_clone(x)
          if not bint.isbint(x) then
             print(debug.traceback())
             assert(bint.isbint(x), 'bint_assert_convert_clone: expected BigInteger, got ' .. type(x) .. ' value ' .. tostring(x))
          end
          local n = setmetatable({}, bint)
          local xi = x
          for i = 1, BINT_SIZE do
             n[i] = xi[i]
          end
          return n
       end
    
    
       local function bint_assert_convert_from_integer(x)
          local xi = bint_frominteger(x)
          assert(xi, 'bint_assert_convert_from_integer: could not convert integer to big integer' .. type(x) .. ' value ' .. tostring(x))
          return xi
       end
    
    
    
    
    
    
    
       function bint.frombase(s, base)
          if type(s) ~= 'string' then
             error('s is not a string')
          end
          base = base or 10
          if not (base >= 2 and base <= 36) then
             error('number base is too large')
          end
          local step = getbasestep(base)
          if #s < step then
    
             return bint_frominteger(tonumber(s, base))
          end
          local sign
          local int
          sign, int = s:lower():match('^([+-]?)(%w+)$')
          if not (sign and int) then
             error('invalid integer string representation')
          end
          local n = bint_zero()
          for i = 1, #int, step do
             local part = int:sub(i, i + step - 1)
             local d = tonumber(part, base)
             if not d then
                error('invalid integer string representation')
             end
             if i > 1 then
                n = n * bint_frominteger(ipow(1, base, #part))
             end
             if d ~= 0 then
                n:_add(bint_frominteger(d))
             end
          end
          if sign == '-' then
             n:_unm()
          end
          return n
       end
       local bint_frombase = bint.frombase
    
    
    
    
    
    
       function bint.fromstring(s)
          if type(s) ~= 'string' then
             error('s is not a string')
          end
          if s:find('^[+-]?[0-9]+$') then
             return bint_frombase(s, 10)
          elseif s:find('^[+-]?0[xX][0-9a-fA-F]+$') then
             return bint_frombase(s:gsub('0[xX]', '', 1), 16)
          elseif s:find('^[+-]?0[bB][01]+$') then
             return bint_frombase(s:gsub('0[bB]', '', 1), 2)
          end
       end
       local bint_fromstring = bint.fromstring
    
    
    
    
    
       function bint.fromle(buffer)
          assert(type(buffer) == 'string', 'buffer is not a string')
          if #buffer > BINT_BYTES then
             buffer = buffer:sub(1, BINT_BYTES)
          elseif #buffer < BINT_BYTES then
             buffer = buffer .. ('\x00'):rep(BINT_BYTES - #buffer)
          end
          return setmetatable({ BINT_LEPACKFMT:unpack(buffer) }, bint)
       end
    
    
    
    
    
       function bint.frombe(buffer)
          assert(type(buffer) == 'string', 'buffer is not a string')
          if #buffer > BINT_BYTES then
             buffer = buffer:sub(-BINT_BYTES, #buffer)
          elseif #buffer < BINT_BYTES then
             buffer = ('\x00'):rep(BINT_BYTES - #buffer) .. buffer
          end
          return setmetatable({ BINT_LEPACKFMT:unpack(buffer:reverse()) }, bint)
       end
    
    
    
    
    
    
       function bint.new(x)
          if getmetatable(x) ~= bint then
             local ty = type(x)
             if ty == 'number' then
                x = bint_frominteger(x)
                assert(x, 'value cannot be represented by a bint')
                return x
             elseif ty == 'string' then
                x = bint_fromstring(x)
                assert(x, 'value cannot be represented by a bint')
                return x
             end
          end
    
          return bint_assert_convert_clone(x)
       end
       local bint_new = bint.new
    
    
    
    
    
    
    
    
       function bint.tobint(x, clone)
          if getmetatable(x) == bint then
             if not clone then
                return bint_assert_convert(x)
             end
    
             return bint_assert_convert_clone(x)
          end
          local ty = type(x)
          if ty == 'number' then
             return bint_frominteger(x)
          elseif ty == 'string' then
             return bint_fromstring(x)
          end
       end
       local tobint = bint.tobint
    
       function bint.touinteger(x)
          if getmetatable(x) == bint then
             local n = 0
             local xi = bint_assert_convert_clone(x)
             for i = 1, BINT_SIZE do
                n = n | (xi[i] << (BINT_WORDBITS * (i - 1)))
             end
             return n
          end
          return tointeger(x)
       end
    
    
    
    
    
    
    
    
    
       function bint.tointeger(x)
          if getmetatable(x) == bint then
             local xi = bint_assert_convert_clone(x)
             local n = 0
             for i = 1, BINT_SIZE do
                n = n | (xi[i] << (BINT_WORDBITS * (i - 1)))
             end
             return n
          end
          return tointeger(x)
       end
    
       local bint_tointeger = bint.tointeger
    
       local function bint_assert_tointeger(x)
          local xi = bint_tointeger(x)
          if not xi then
             error('bint_assert_tointeger: cannot convert to integer, got ' .. type(x) .. ' value ' .. tostring(x))
          end
          return xi
       end
    
    
    
    
    
    
    
       function bint.tonumber(x)
          x = bint_assert_convert_clone(x)
          if x:le(BINT_MATHMAXINTEGER) and x:ge(BINT_MATHMININTEGER) then
             return x:tointeger()
          end
          print('warning: too big for int, casting to number, potential precision loss')
          return tonumber(x)
       end
       local bint_tonumber = bint.tonumber
    
    
       local BASE_LETTERS = {}
       do
          for i = 1, 36 do
             BASE_LETTERS[i - 1] = ('0123456789abcdefghijklmnopqrstuvwxyz'):sub(i, i)
          end
       end
    
    
    
    
    
    
    
    
    
    
       function bint.tobase(x, base, unsigned)
          x = bint_assert_convert_clone(x)
          if not x then
             error('x is a fractional float or something else')
          end
          base = base or 10
          if not (base >= 2 and base <= 36) then
    
             return
          end
          if unsigned == nil then
             unsigned = base ~= 10
          end
          local isxneg = x:isneg()
          if (base == 10 and not unsigned) or (base == 16 and unsigned and not isxneg) then
             if x:le(BINT_MATHMAXINTEGER) and x:ge(BINT_MATHMININTEGER) then
    
                local n = x:tointeger()
                if base == 10 then
                   return tostring(n)
                elseif unsigned then
                   return string_format('%x', n)
                end
             end
          end
          local ss = {}
          local neg = not unsigned and isxneg
          x = neg and x:abs() or bint_new(x)
          local xiszero = x:iszero()
          if xiszero then
             return '0'
          end
    
          local step = 0
          local basepow = 1
          local limit = (BINT_WORDMSB - 1) // base
          repeat
             step = step + 1
             basepow = basepow * base
          until basepow >= limit
    
          local size = BINT_SIZE
          local xd
          local carry
          local d
          repeat
    
             carry = 0
             xiszero = true
             for i = size, 1, -1 do
                carry = carry | x[i]
                d, xd = carry // basepow, carry % basepow
                if xiszero and d ~= 0 then
                   size = i
                   xiszero = false
                end
                x[i] = d
                carry = xd << BINT_WORDBITS
             end
    
             for _ = 1, step do
                xd, d = xd // base, xd % base
                if xiszero and xd == 0 and d == 0 then
    
                   break
                end
                table_insert(ss, 1, BASE_LETTERS[d])
             end
          until xiszero
          if neg then
             table_insert(ss, 1, '-')
          end
          return table_concat(ss)
       end
    
    
    
    
    
    
    
    
       function bint.tole(x, trim)
          x = bint_assert_convert_clone(x)
          local s = BINT_LEPACKFMT:pack(table_unpack(x))
          if trim then
             s = s:gsub('\x00+$', '')
             if s == '' then
                s = '\x00'
             end
          end
          return s
       end
    
    
    
    
    
    
       function bint.tobe(x, trim)
          x = bint_assert_convert_clone(x)
          local xt = { table_unpack(x) }
          local s = BINT_LEPACKFMT:pack(table_unpack(xt)):reverse()
          if trim then
             s = s:gsub('^\x00+', '')
             if s == '' then
                s = '\x00'
             end
          end
          return s
       end
    
    
    
       function bint.iszero(x)
          local xi = bint_assert_convert(x)
          for i = 1, BINT_SIZE do
             if xi[i] ~= 0 then
                return false
             end
          end
          return true
       end
    
    
    
       function bint.isone(x)
          local xi = bint_assert_convert(x)
          if xi[1] ~= 1 then
             return false
          end
          for i = 2, BINT_SIZE do
             if xi[i] ~= 0 then
                return false
             end
          end
          return true
       end
    
    
    
       function bint.isminusone(x)
          local xi = bint_assert_convert(x)
          if xi[1] ~= BINT_WORDMAX then
             return false
          end
          return true
       end
       local bint_isminusone = bint.isminusone
    
    
    
       function bint.isintegral(x)
          return getmetatable(x) == bint or math_type(x) == 'integer'
       end
    
    
    
       function bint.isnumeric(x)
          return getmetatable(x) == bint or type(x) == 'number'
       end
    
    
    
    
    
       function bint.type(x)
          if getmetatable(x) == bint then
             return 'bint'
          end
          return math_type(x)
       end
    
    
    
    
       function bint.isneg(x)
          bint_assert_convert(x)
          return x[BINT_SIZE] & BINT_WORDMSB ~= 0
       end
       local bint_isneg = bint.isneg
    
    
    
       function bint.ispos(x)
          bint_assert_convert(x)
          return not x:isneg() and not x:iszero()
       end
    
    
    
       function bint.iseven(x)
          bint_assert_convert(x)
          return x[1] & 1 == 0
       end
    
    
    
       function bint.isodd(x)
          bint_assert_convert(x)
          return x[1] & 1 == 1
       end
    
    
       function bint.maxinteger()
          local x = setmetatable({}, bint)
          for i = 1, BINT_SIZE - 1 do
             x[i] = BINT_WORDMAX
          end
          x[BINT_SIZE] = BINT_WORDMAX ~ BINT_WORDMSB
          return x
       end
    
    
       function bint.mininteger()
          local x = setmetatable({}, bint)
          for i = 1, BINT_SIZE - 1 do
             x[i] = 0
          end
          x[BINT_SIZE] = BINT_WORDMSB
          return x
       end
    
    
       function bint:_shlone()
          local wordbitsm1 = BINT_WORDBITS - 1
          for i = BINT_SIZE, 2, -1 do
             self[i] = ((self[i] << 1) | (self[i - 1] >> wordbitsm1)) & BINT_WORDMAX
          end
          self[1] = (self[1] << 1) & BINT_WORDMAX
          return self
       end
    
    
       function bint:_shrone()
          local wordbitsm1 = BINT_WORDBITS - 1
          for i = 1, BINT_SIZE - 1 do
             self[i] = ((self[i] >> 1) | (self[i + 1] << wordbitsm1)) & BINT_WORDMAX
          end
          self[BINT_SIZE] = self[BINT_SIZE] >> 1
          return self
       end
    
    
       function bint:_shlwords(n)
          for i = BINT_SIZE, n + 1, -1 do
             self[i] = self[i - n]
          end
          for i = 1, n do
             self[i] = 0
          end
          return self
       end
    
    
       function bint:_shrwords(n)
          if n < BINT_SIZE then
             for i = 1, BINT_SIZE - n do
                self[i] = self[i + n]
             end
             for i = BINT_SIZE - n + 1, BINT_SIZE do
                self[i] = 0
             end
          else
             for i = 1, BINT_SIZE do
                self[i] = 0
             end
          end
          return self
       end
    
    
       function bint:_inc()
          for i = 1, BINT_SIZE do
             local tmp = self[i]
             local v = (tmp + 1) & BINT_WORDMAX
             self[i] = v
             if v > tmp then
                break
             end
          end
          return self
       end
    
    
    
       function bint.inc(x)
          local ix = bint_assert_convert(x)
          return ix:_inc()
       end
    
    
       function bint:_dec()
          for i = 1, BINT_SIZE do
             local tmp = self[i]
             local v = (tmp - 1) & BINT_WORDMAX
             self[i] = v
             if v <= tmp then
                break
             end
          end
          return self
       end
    
    
    
       function bint.dec(x)
          local ix = bint_assert_convert(x)
          return ix:_dec()
       end
    
    
    
    
       function bint:_assign(y)
          y = bint_assert_convert(y)
          for i = 1, BINT_SIZE do
             self[i] = y[i]
          end
          return self
       end
    
    
       function bint:_abs()
          if self:isneg() then
             self:_unm()
          end
          return self
       end
    
    
    
       function bint.abs(x)
          local ix = bint_assert_convert_clone(x)
          return ix:_abs()
       end
       local bint_abs = bint.abs
    
    
    
       function bint.floor(x)
          return bint_assert_convert_clone(x)
       end
    
    
    
       function bint.ceil(x)
          return bint_assert_convert_clone(x)
       end
    
    
    
    
       function bint.bwrap(x, y)
          x = bint_assert_convert(x)
          if y <= 0 then
             return bint_zero()
          elseif y < BINT_BITS then
             local tmp = (bint_one() << y)
             local tmp2 = tmp:_dec():tointeger()
             return x & tmp2
          end
          return bint_new(x)
       end
    
    
    
    
       function bint.brol(x, y)
          x, y = bint_assert_convert(x), bint_assert_tointeger(y)
          if y > 0 then
             return (x << y) | (x >> (BINT_BITS - y))
          elseif y < 0 then
             if y ~= math_mininteger then
                return x:bror(-y)
             else
                x:bror(-(y + 1))
                x:bror(1)
             end
          end
          return x
       end
    
    
    
    
       function bint.bror(x, y)
          x, y = bint_assert_convert(x), bint_assert_tointeger(y)
          if y > 0 then
             return (x >> y) | (x << (BINT_BITS - y))
          elseif y < 0 then
             if y ~= math_mininteger then
                return x:brol(-y)
             else
                x:brol(-(y + 1))
                x:brol(1)
             end
          end
          return x
       end
    
    
    
    
    
       function bint.max(x, y)
          local ix = bint_assert_convert(x)
          local iy = bint_assert_convert(y)
          return bint_new(ix:gt(iy) and ix or iy)
       end
    
    
    
    
    
       function bint.min(x, y)
          local ix = bint_assert_convert(x)
          local iy = bint_assert_convert(y)
          return bint_new(ix:lt(iy) and ix or iy)
       end
    
    
    
    
       function bint:_add(y)
          y = bint_assert_convert(y)
          local carry = 0
          for i = 1, BINT_SIZE do
             local tmp = self[i] + y[i] + carry
             carry = tmp >> BINT_WORDBITS
             self[i] = tmp & BINT_WORDMAX
          end
          return self
       end
    
    
    
    
       function bint.__add(x, y)
          local ix = bint_assert_convert(x)
          local iy = bint_assert_convert(y)
          local z = setmetatable({}, bint)
          local carry = 0
          for i = 1, BINT_SIZE do
             local tmp = ix[i] + iy[i] + carry
             carry = tmp >> BINT_WORDBITS
             z[i] = tmp & BINT_WORDMAX
          end
          return z
       end
    
    
    
    
       function bint:_sub(y)
          y = bint_assert_convert(y)
          local borrow = 0
          local wordmaxp1 = BINT_WORDMAX + 1
          for i = 1, BINT_SIZE do
             local res = self[i] + wordmaxp1 - y[i] - borrow
             self[i] = res & BINT_WORDMAX
             borrow = (res >> BINT_WORDBITS) ~ 1
          end
          return self
       end
    
    
    
    
       function bint.__sub(x, y)
          local ix = bint_assert_convert(x)
          local iy = bint_assert_convert(y)
          local z = setmetatable({}, bint)
          local borrow = 0
          local wordmaxp1 = BINT_WORDMAX + 1
          for i = 1, BINT_SIZE do
             local res = ix[i] + wordmaxp1 - iy[i] - borrow
             z[i] = res & BINT_WORDMAX
             borrow = (res >> BINT_WORDBITS) ~ 1
          end
          return z
       end
    
    
    
    
       function bint.__mul(x, y)
          local ix = bint_assert_convert(x)
          local iy = bint_assert_convert(y)
          local z = bint_zero()
          local sizep1 = BINT_SIZE + 1
          local s = sizep1
          local e = 0
          for i = 1, BINT_SIZE do
             if ix[i] ~= 0 or iy[i] ~= 0 then
                e = math_max(e, i)
                s = math_min(s, i)
             end
          end
          for i = s, e do
             for j = s, math_min(sizep1 - i, e) do
                local a = ix[i] * iy[j]
                if a ~= 0 then
                   local carry = 0
                   for k = i + j - 1, BINT_SIZE do
                      local tmp = z[k] + (a & BINT_WORDMAX) + carry
                      carry = tmp >> BINT_WORDBITS
                      z[k] = tmp & BINT_WORDMAX
                      a = a >> BINT_WORDBITS
                   end
                end
             end
          end
          return z
       end
    
    
    
    
       function bint.__eq(x, y)
          bint_assert_convert(x)
          bint_assert_convert(y)
          for i = 1, BINT_SIZE do
             if x[i] ~= y[i] then
                return false
             end
          end
          return true
       end
    
    
    
    
       function bint.eq(x, y)
          local ix = bint_assert_convert(x)
          local iy = bint_assert_convert(y)
          return ix == iy
       end
       local bint_eq = bint.eq
    
       local function findleftbit(x)
          for i = BINT_SIZE, 1, -1 do
             local v = x[i]
             if v ~= 0 then
                local j = 0
                repeat
                   v = v >> 1
                   j = j + 1
                until v == 0
                return (i - 1) * BINT_WORDBITS + j - 1, i
             end
          end
       end
    
    
       local function sudivmod(nume, deno)
          local rema
          local carry = 0
          for i = BINT_SIZE, 1, -1 do
             carry = carry | nume[i]
             nume[i] = carry // deno
             rema = carry % deno
             carry = rema << BINT_WORDBITS
          end
          return rema
       end
    
    
    
    
    
    
    
    
    
    
       function bint.udivmod(x, y)
          local nume = bint_assert_convert_clone(x)
          local deno = bint_assert_convert(y)
    
          local ishighzero = true
          for i = 2, BINT_SIZE do
             if deno[i] ~= 0 then
                ishighzero = false
                break
             end
          end
          if ishighzero then
    
             local low = deno[1]
             assert(low ~= 0, 'attempt to divide by zero')
             if low == 1 then
    
                return nume, bint_zero()
             elseif low <= (BINT_WORDMSB - 1) then
    
                local rema = sudivmod(nume, low)
                return nume, bint_fromuinteger(rema)
             end
          end
          if nume:ult(deno) then
    
             return bint_zero(), nume
          end
    
          local denolbit = findleftbit(deno)
          local numelbit, numesize = findleftbit(nume)
          local bit = numelbit - denolbit
          deno = deno << bit
          local wordmaxp1 = BINT_WORDMAX + 1
          local wordbitsm1 = BINT_WORDBITS - 1
          local denosize = numesize
          local quot = bint_zero()
          while bit >= 0 do
    
             local le = true
             local size = math_max(numesize, denosize)
             for i = size, 1, -1 do
                local a, b = deno[i], nume[i]
                if a ~= b then
                   le = a < b
                   break
                end
             end
    
             if le then
    
                local borrow = 0
                for i = 1, size do
                   local res = nume[i] + wordmaxp1 - deno[i] - borrow
                   nume[i] = res & BINT_WORDMAX
                   borrow = (res >> BINT_WORDBITS) ~ 1
                end
    
                local i = (bit // BINT_WORDBITS) + 1
                quot[i] = quot[i] | (1 << (bit % BINT_WORDBITS))
             end
    
             for i = 1, denosize - 1 do
                deno[i] = ((deno[i] >> 1) | (deno[i + 1] << wordbitsm1)) & BINT_WORDMAX
             end
             local lastdenoword = deno[denosize] >> 1
             deno[denosize] = lastdenoword
    
             if lastdenoword == 0 then
                while deno[denosize] == 0 do
                   denosize = denosize - 1
                end
                if denosize == 0 then
                   break
                end
             end
    
             bit = bit - 1
          end
    
          return quot, nume
       end
       local bint_udivmod = bint.udivmod
    
    
    
    
    
    
    
       function bint.udiv(x, y)
          bint_assert_convert(x)
          bint_assert_convert(y)
          return (bint_udivmod(x, y))
       end
    
    
    
    
    
    
    
       function bint.umod(x, y)
          bint_assert_convert(x)
          bint_assert_convert(y)
          local _, rema = bint_udivmod(x, y)
          return rema
       end
       local bint_umod = bint.umod
    
    
    
    
    
    
    
    
    
       function bint.tdivmod(x, y)
          bint_assert_convert(x)
          bint_assert_convert(y)
          local ax
          local ay
          ax, ay = bint_abs(x), bint_abs(y)
    
          local ix
          local iy
          ix, iy = tobint(ax), tobint(ay)
          local quot
          local rema
          if ix and iy then
             assert(not (bint_eq(x, BINT_MININTEGER) and bint_isminusone(y)), 'division overflow')
             quot, rema = bint_udivmod(ix, iy)
          else
             quot, rema = ax // ay, ax % ay
          end
          local isxneg
          local isyneg
          isxneg, isyneg = bint_isneg(x), bint_isneg(y)
    
          if isxneg ~= isyneg then
             quot = -quot
          end
          if isxneg then
             rema = -rema
          end
          return quot, rema
       end
       local bint_tdivmod = bint.tdivmod
    
    
    
    
    
    
    
       function bint.tdiv(x, y)
          bint_assert_convert(x)
          bint_assert_convert(y)
          return (bint_tdivmod(x, y))
       end
    
    
    
    
    
    
    
    
       function bint.tmod(x, y)
          local _, rema = bint_tdivmod(x, y)
          return rema
       end
    
    
    
    
    
    
    
    
    
    
       function bint.idivmod(x, y)
          local ix = bint_assert_convert(x)
          local iy = bint_assert_convert(y)
          local isnumeneg = ix[BINT_SIZE] & BINT_WORDMSB ~= 0
          local isdenoneg = iy[BINT_SIZE] & BINT_WORDMSB ~= 0
          if isnumeneg then
             ix = -ix
          end
          if isdenoneg then
             iy = -iy
          end
          local quot
          local rema
          quot, rema = bint_udivmod(ix, iy)
          if isnumeneg ~= isdenoneg then
             quot:_unm()
    
             if not rema:iszero() then
                quot:_dec()
    
                if isnumeneg and not isdenoneg then
                   rema:_unm():_add(y)
                elseif isdenoneg and not isnumeneg then
                   rema:_add(y)
                end
             end
          elseif isnumeneg then
    
             rema:_unm()
          end
          return quot, rema
       end
       local bint_idivmod = bint.idivmod
    
    
    
    
    
    
    
    
       function bint.__idiv(x, y)
          local ix = bint_assert_convert(x)
          local iy = bint_assert_convert(y)
          local isnumeneg = ix[BINT_SIZE] & BINT_WORDMSB ~= 0
          local isdenoneg = iy[BINT_SIZE] & BINT_WORDMSB ~= 0
          if isnumeneg then
             ix = -ix
          end
          if isdenoneg then
             iy = -iy
          end
          local quot
          local rema
          quot, rema = bint_udivmod(ix, iy)
          if isnumeneg ~= isdenoneg then
             quot:_unm()
    
             if not rema:iszero() then
                quot:_dec()
             end
          end
          return quot, rema
       end
    
    
    
    
    
    
    
    
    
       function bint.__mod(x, y)
          local _, rema = bint_idivmod(x, y)
          return rema
       end
    
    
    
    
    
    
    
    
    
       function bint.ipow(x, y)
          local ix = bint_assert_convert(x)
          local iy = bint_assert_convert(y)
          if iy:iszero() then
             return bint_one()
          elseif iy:isone() then
             return bint_new(ix)
          end
    
          x, y = bint_new(x), bint_new(y)
          local z = bint_one()
          repeat
             if y:iseven() then
                x = x * x
                y:_shrone()
             else
                z = x * z
                x = x * x
                y:_dec():_shrone()
             end
          until y:isone()
          return x * z
       end
    
    
    
    
    
    
    
    
    
       function bint.upowmod(x, y, m)
          local mi = bint_assert_convert(m)
          if mi:isone() then
             return bint_zero()
          end
          local xi = bint_new(x)
          local yi = bint_new(y)
          local z = bint_one()
          xi = bint_umod(xi, mi)
          while not yi:iszero() do
             if yi:isodd() then
                z = bint_umod(z * xi, mi)
             end
             yi:_shrone()
             xi = bint_umod(xi * xi, mi)
          end
          return z
       end
    
    
    
    
    
    
    
       function bint.__shl(x, y)
          x, y = bint_assert_convert_clone(x), bint_assert_tointeger(y)
          if y == math_mininteger or math_abs(y) >= BINT_BITS then
             return bint_zero()
          end
          if y < 0 then
             return x >> -y
          end
          local nvals = y // BINT_WORDBITS
          if nvals ~= 0 then
             x:_shlwords(nvals)
             y = y - nvals * BINT_WORDBITS
          end
          if y ~= 0 then
             local wordbitsmy = BINT_WORDBITS - y
             for i = BINT_SIZE, 2, -1 do
                x[i] = ((x[i] << y) | (x[i - 1] >> wordbitsmy)) & BINT_WORDMAX
             end
             x[1] = (x[1] << y) & BINT_WORDMAX
          end
          return x
       end
    
    
    
    
    
    
       function bint.__shr(x, y)
          x, y = bint_assert_convert_clone(x), bint_assert_tointeger(y)
          if y == math_mininteger or math_abs(y) >= BINT_BITS then
             return bint_zero()
          end
          if y < 0 then
             return x << -y
          end
          local nvals = y // BINT_WORDBITS
          if nvals ~= 0 then
             x:_shrwords(nvals)
             y = y - nvals * BINT_WORDBITS
          end
          if y ~= 0 then
             local wordbitsmy = BINT_WORDBITS - y
             for i = 1, BINT_SIZE - 1 do
                x[i] = ((x[i] >> y) | (x[i + 1] << wordbitsmy)) & BINT_WORDMAX
             end
             x[BINT_SIZE] = x[BINT_SIZE] >> y
          end
          return x
       end
    
    
    
    
       function bint:_band(y)
          local yi = bint_assert_convert_from_integer(y)
          for i = 1, BINT_SIZE do
             self[i] = self[i] & yi[i]
          end
          return self
       end
    
    
    
    
    
       function bint.__band(x, y)
          return bint_assert_convert_clone(x):_band(y)
       end
    
    
    
    
       function bint:_bor(y)
          y = bint_assert_convert(y)
          for i = 1, BINT_SIZE do
             self[i] = self[i] | y[i]
          end
          return self
       end
    
    
    
    
    
       function bint.__bor(x, y)
          return bint_assert_convert_clone(x):_bor(y)
       end
    
    
    
    
       function bint:_bxor(y)
          y = bint_assert_convert(y)
          for i = 1, BINT_SIZE do
             self[i] = self[i] ~ y[i]
          end
          return self
       end
    
    
    
    
    
       function bint.__bxor(x, y)
          return bint_assert_convert_clone(x):_bxor(y)
       end
    
    
       function bint:_bnot()
          for i = 1, BINT_SIZE do
             self[i] = (~self[i]) & BINT_WORDMAX
          end
          return self
       end
    
       function bint.__bnot(x)
          local y = setmetatable({}, bint)
          for i = 1, BINT_SIZE do
             y[i] = (~x[i]) & BINT_WORDMAX
          end
          return y
       end
    
    
       function bint:_unm()
          return self:_bnot():_inc()
       end
    
    
    
       function bint.__unm(x)
          return (~x):_inc()
       end
    
    
    
    
    
    
       function bint.ult(x, y)
          for i = BINT_SIZE, 1, -1 do
             local a = x[i]
             local b = y[i]
             if a ~= b then
                return a < b
             end
          end
          return false
       end
    
    
    
    
    
    
       function bint.ule(x, y)
          x, y = bint_assert_convert(x), bint_assert_convert(y)
          for i = BINT_SIZE, 1, -1 do
             local a = x[i]
             local b = y[i]
             if a ~= b then
                return a < b
             end
          end
          return true
       end
    
    
    
    
    
       function bint.lt(x, y)
          local ix = bint_assert_convert(x)
          local iy = bint_assert_convert(y)
    
          local xneg = ix[BINT_SIZE] & BINT_WORDMSB ~= 0
          local yneg = iy[BINT_SIZE] & BINT_WORDMSB ~= 0
          if xneg == yneg then
             for i = BINT_SIZE, 1, -1 do
                local a = ix[i]
                local b = iy[i]
                if a ~= b then
                   return a < b
                end
             end
             return false
          end
          return xneg and not yneg
       end
    
       function bint:gt(y)
          return not self:eq(y) and not self:lt(y)
       end
    
    
    
    
    
       function bint.le(x, y)
          local ix = bint_assert_convert(x)
          local iy = bint_assert_convert(y)
          local xneg = ix[BINT_SIZE] & BINT_WORDMSB ~= 0
          local yneg = iy[BINT_SIZE] & BINT_WORDMSB ~= 0
          if xneg == yneg then
             for i = BINT_SIZE, 1, -1 do
                local a = ix[i]
                local b = iy[i]
                if a ~= b then
                   return a < b
                end
             end
             return true
          end
          return xneg and not yneg
       end
    
       function bint:ge(y)
          return self:eq(y) or self:gt(y)
       end
    
    
    
       function bint:__tostring()
          return self:tobase(10)
       end
    
    
       setmetatable(bint, {
          __call = function(_, x)
             return bint_new(x)
          end,
       })
    
       BINT_MATHMININTEGER, BINT_MATHMAXINTEGER = bint_new(_tl_math_mininteger), bint_new(_tl_math_maxinteger)
       BINT_MININTEGER = bint.mininteger()
       memo[memoindex] = bint
    
       return bint
    
    end
    
    return newmodule
    end
    end
    
    do
    local _ENV = _ENV
    package.preload[ "utils.tl-utils" ] = function( ... ) local arg = _G.arg;
    local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pairs = _tl_compat and _tl_compat.pairs or pairs; local table = _tl_compat and _tl_compat.table or table
    
    
    
    
    
    local function find(predicate, arr)
       for _, value in ipairs(arr) do
          if predicate(value) then
             return value
          end
       end
       return nil
    end
    
    local function filter(predicate, arr)
       local result = {}
       for _, value in ipairs(arr) do
          if predicate(value) then
             table.insert(result, value)
          end
       end
       return result
    end
    
    local function reduce(reducer, initialValue, arr)
       local result = initialValue
       for i, value in ipairs(arr) do
          result = reducer(result, value, i, arr)
       end
       return result
    end
    
    
    local function map(mapper, arr)
       local result = {}
       for i, value in ipairs(arr) do
          result[i] = mapper(value, i, arr)
       end
       return result
    end
    
    local function reverse(arr)
       local result = {}
       for i = #arr, 1, -1 do
          table.insert(result, arr[i])
       end
       return result
    end
    
    local function compose(...)
       local funcs = { ... }
       return function(x)
          for i = #funcs, 1, -1 do
             x = funcs[i](x)
          end
          return x
       end
    end
    
    local function keys(xs)
       local ks = {}
       for k, _ in pairs(xs) do
          table.insert(ks, k)
       end
       return ks
    end
    
    local function values(xs)
       local vs = {}
       for _, v in pairs(xs) do
          table.insert(vs, v)
       end
       return vs
    end
    
    local function includes(value, arr)
       for _, v in ipairs(arr) do
          if v == value then
             return true
          end
       end
       return false
    end
    
    return {
       find = find,
       filter = filter,
       reduce = reduce,
       map = map,
       reverse = reverse,
       compose = compose,
       values = values,
       keys = keys,
       includes = includes,
    }
    end
    end
    
    require("agent.globals")
    local agent = require('agent.agent')
    
    
    Handlers.add(
    'Info',
    Handlers.utils.hasMatchingTag('Action', 'Info'),
    agent.handleInfo)
    
    
    Handlers.add(
    'Set-Strategy',
    Handlers.utils.hasMatchingTag('Action', 'Set-Strategy'),
    agent.handleSetStrategy)
    
    
    Handlers.add(
    'Top-Up-Credit-Notice',
    agent.isTopUpCreditNotice,
    agent.handleTopUpCreditNotice)
    
    
    Handlers.add(
    'Subscription-Confirmation',
    agent.isSusbcriptionConfirmation,
    agent.handleSubscriptionConfirmation)
    
    
    Handlers.add(
    'Swap-Params-Update',
    agent.isAmmUpdate,
    agent.handleAmmUpdate)
    
    
    Handlers.add(
    'Cancel',
    agent.isCancellation,
    agent.handleCancellation)
    
    
    Handlers.add(
    'Check-Expiration',
    agent.isExpirationCheck,
    agent.handleExpirationCheck)
    
    
    Handlers.add(
    'Emergency-Withdrawal',
    agent.isEmergencyWithdrawal,
    agent.handleEmergencyWithdrawal)
    
    
    Handlers.add(
    'Cron-Tick',
    agent.isCronTick,
    agent.handleCronTick)
    
   
    Handlers.add(
    'Cron-Tick-Confirmation',
    agent.isCronTickConfirmation,
    agent.handleCronTickConfirmation)
    
      ao.send({
        Target = 'x_WysdFwKD_buywRK9qLA7IexdlsvVTVq6ESWMRCzFY',
        Action = 'Eval-Confirmation'
      })
    