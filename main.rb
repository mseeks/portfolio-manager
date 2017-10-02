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

puts "BUY: ".bold.black + buy_list.sort.join(", ")
puts "SELL: ".bold.black + sell_list.sort.join(", ")

pass_count = 1

def rebalance(buy_list, sell_list, pass_count)
  @portfolio = Robinhood.new

  return unless buy_list.length > 0

  buy_list = buy_list.sort_by do |stock|
    @portfolio.last_price_for(stock)
  end

  cash_per_potential_buy = (@portfolio.cash / buy_list.length).round(2)

  formatted_cash = Money.new((@portfolio.cash.round(2) * 100).to_i, "USD").format
  formatted_cash_per_potential_buy = Money.new((cash_per_potential_buy.round(2) * 100).to_i, "USD").format

  puts "\n"
  puts "REBALANCE ##{pass_count}: ".bold.black + buy_list.join(", ") + " -> " + "#{formatted_cash_per_potential_buy}/BUY".bold.black
  pass_count = pass_count + 1

  account_number = @portfolio.account["account_number"]

  non_owned_buy_list = Array.new(buy_list)

  @portfolio.positions.each do |position|
    open_orders = @portfolio.open_orders_for(position)
    instrument = @portfolio.instrument_for_position(position)
    symbol = instrument["symbol"]
    last_price = @portfolio.last_price_for(symbol)
    formatted_last_price = Money.new((last_price.round(2) * 100).to_i, "USD").format
    quantity = position["quantity"].to_f.round
    average_buy_price = Money.new((position["average_buy_price"].to_f.round(2) * 100).to_i, "USD").format

    if open_orders.length == 0
      if sell_list.include?(symbol)
        puts "  SELL #{quantity} x #{symbol} @ #{formatted_last_price}".bold.green

        @portfolio.market_sell(symbol, position["instrument"], quantity)
      elsif buy_list.include?(symbol)
        buy_count = (cash_per_potential_buy / last_price).floor

        if buy_count > 0
          puts "  BUY #{buy_count} x #{symbol} @ #{formatted_last_price} ".bold.red + "|" + " HOLD  #{quantity} x #{symbol} @ #{average_buy_price}".bold.yellow
          @portfolio.market_buy(symbol, position["instrument"], buy_count)
        else
          puts "  HOLD #{quantity} x #{symbol} @ #{average_buy_price}".bold.yellow
        end

        non_owned_buy_list.delete(symbol)
      else
        puts "  HOLD #{quantity} x #{symbol} @ #{average_buy_price}".yellow
      end
    else
      puts "  PEND #{quantity} x #{symbol} @ #{average_buy_price}".magenta
    end
  end

  non_owned_buy_list.each do |stock|
    last_price = @portfolio.last_price_for(stock)
    formatted_last_price = Money.new((last_price.round(2) * 100).to_i, "USD").format
    buy_count = (cash_per_potential_buy / last_price).floor

    if buy_count > 0
      puts "  BUY #{buy_count} x #{stock} @ #{formatted_last_price}".bold.red
      @portfolio.market_buy(stock, @portfolio.instrument_for_symbol(stock), buy_count)
    else
      puts "  STAY #{buy_count} x #{stock} @ #{formatted_last_price}".bold.yellow
    end
  end

  buy_list.pop

  rebalance(buy_list, sell_list, pass_count)
end

rebalance(buy_list, sell_list, pass_count)
