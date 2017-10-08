require "colorize"
require "json"
require "money"
require "rest-client"
require "./lib/alpha_vantage"
require "./lib/robinhood"

Money.use_i18n = false

potential_securities = ENV["POTENTIAL_SECURITIES"].split(",")

buy_list, sell_list = [], []

potential_securities.each do |potential_security|
  query = AlphaVantage.new(potential_security)

  (query.macd > query.signal ? buy_list : sell_list) << potential_security
end

portfolio = Robinhood.new

buy_list = buy_list.sort_by do |stock|
  portfolio.last_price_for(stock)
end

sell_list = sell_list.sort_by do |stock|
  portfolio.last_price_for(stock)
end

puts "SIGNALED BUY: ".bold.black + buy_list.join(", ")
puts "SIGNALED SELL: ".bold.black + sell_list.join(", ")

$stdout.flush

pass_count = 1

def rebalance_sells(sell_list)
  return unless sell_list.length > 0

  puts "\n"
  puts "REBALANCE SELL: ".bold.black + sell_list.join(", ")

  portfolio = Robinhood.new

  portfolio.positions.each do |position|
    open_orders = portfolio.open_orders_for(position)
    instrument = portfolio.instrument_for_position(position)
    symbol = instrument["symbol"]
    last_price = portfolio.last_price_for(symbol)
    quantity = position["quantity"].to_f.round

    if sell_list.include?(symbol)
      puts "  SELL #{quantity} x #{symbol} @ #{format_money(last_price)}".bold.green
      portfolio.market_sell(symbol, position["instrument"], quantity)
    end

    sell_orders = open_orders.reject{|o| o["side"]!= "sell" }

    if sell_orders.length > 0
      sell_quantity = sell_orders.map{|o| o["quantity"].to_f.round }.reduce(0, :+)
      average_sell_price = format_money(sell_orders.map{|o| o["price"].to_f * o["quantity"].to_f.round }.reduce(0, :+) / sell_quantity)

      puts "  SELL #{sell_quantity} x #{symbol} @ #{average_sell_price} ~".yellow
    end
  end

  $stdout.flush
end

def rebalance_buys(buy_list, pass_count)
  return unless buy_list.length > 0

  portfolio = Robinhood.new

  cash_per_potential_buy = (portfolio.cash / buy_list.length).round(2)
  return_early = if portfolio.last_price_for(buy_list.last) > cash_per_potential_buy
    buy_list.pop
    rebalance_buys(buy_list, pass_count)

    true
  end

  return if return_early

  formatted_cash = format_money(portfolio.cash)
  formatted_cash_per_potential_buy = format_money(cash_per_potential_buy)

  puts "\n"
  puts "REBALANCE BUY ##{pass_count}: ".bold.black + buy_list.join(", ") + " -> " + "#{formatted_cash_per_potential_buy}/BUY".bold.black
  pass_count = pass_count + 1

  account_number = portfolio.account["account_number"]

  non_owned_buy_list = Array.new(buy_list)

  portfolio.positions.each do |position|
    open_orders = portfolio.open_orders_for(position)
    instrument = portfolio.instrument_for_position(position)
    symbol = instrument["symbol"]
    last_price = portfolio.last_price_for(symbol)
    formatted_last_price = format_money(last_price)
    quantity = position["quantity"].to_f.round
    average_buy_price = format_money(position["average_buy_price"].to_f)

    if buy_list.include?(symbol)
      buy_count = (cash_per_potential_buy / last_price).floor

      if buy_count > 0
        puts "  BUY #{buy_count} x #{symbol} @ #{formatted_last_price} ".bold.red
        portfolio.market_buy(symbol, position["instrument"], buy_count)

        puts "  HOLD #{quantity} x #{symbol} @ #{average_buy_price}".bold.blue unless quantity == 0
      else
        puts "  HOLD #{quantity} x #{symbol} @ #{average_buy_price}".bold.blue unless quantity == 0
      end

      non_owned_buy_list.delete(symbol)
    else
      puts "  HOLD #{quantity} x #{symbol} @ #{average_buy_price}".blue unless quantity == 0
    end

    buy_orders = open_orders.reject{|o| o["side"]!= "buy" }

    if buy_orders.length > 0
      buy_quantity = buy_orders.map{|o| o["quantity"].to_f.round }.reduce(0, :+)
      average_buy_price = format_money(buy_orders.map{|o| o["price"].to_f * o["quantity"].to_f.round }.reduce(0, :+) / buy_quantity)

      puts "  BUY #{buy_quantity} x #{symbol} @ #{average_buy_price} ~".yellow
    end
  end

  non_owned_buy_list.each do |stock|
    last_price = portfolio.last_price_for(stock)
    formatted_last_price = format_money(last_price)
    buy_count = (cash_per_potential_buy / last_price).floor

    if buy_count > 0
      puts "  BUY #{buy_count} x #{stock} @ #{formatted_last_price}".bold.red
      portfolio.market_buy(stock, portfolio.instrument_for_symbol(stock)["url"], buy_count)
    else
      puts "  STAY #{buy_count} x #{stock} @ #{formatted_last_price}".bold.blue
    end
  end

  buy_list.pop

  $stdout.flush

  rebalance_buys(buy_list, pass_count)
end

def format_money(amount)
  Money.new((amount.round(2) * 100).to_i, "USD").format
end

rebalance_sells(sell_list)
rebalance_buys(buy_list, pass_count)
