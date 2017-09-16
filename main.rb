require "json"
require "rest-client"

robinhood_access_token = ENV["ROBINHOOD_TOKEN"]

robinhood_headers = {
  accept: "application/json",
  Authorization: "Token #{robinhood_access_token}"
}

robinhood = RestClient::Resource.new("https://api.robinhood.com")

account_number = JSON.parse(robinhood["accounts/"].get(robinhood_headers).body)["results"].first["account_number"]
positions = JSON.parse(robinhood["accounts/#{account_number}/positions/?nonzero=true"].get(robinhood_headers).body)["results"]
orders = JSON.parse(robinhood["orders/"].get(robinhood_headers).body)["results"]

current_instruments = positions.map{|p| p["instrument"] }
active_orders = orders.select do |order|
  current_instruments.include?(order["instrument"]) && (order["state"] == "confirmed" || order["state"] == "queued")
end

positions.each do |position|
  position_id_matcher = /[^\/]+(?=\/$|$)/

  open_orders_for_position = active_orders.select do |order|
    first_id = position_id_matcher.match(order["position"])[0]
    second_id = position_id_matcher.match(position["url"])[0]

    first_id == second_id
  end

  if open_orders_for_position.length == 0
    instrument = JSON.parse(RestClient.get(position["instrument"], robinhood_headers).body)
    average_buy_price = position["average_buy_price"].to_f
    target_gain = ENV["TARGET_PERCENT_GAIN"].to_f / 100.00
    limit_price = (average_buy_price * (1.0 + target_gain)).round(2)

    robinhood["orders/"].post({
      account: "https://api.robinhood.com/accounts/#{account_number}/",
      instrument: position["instrument"],
      symbol: instrument["symbol"],
      type: "limit",
      price: limit_price,
      trigger: "immediate",
      quantity: position["quantity"],
      side: "sell",
      time_in_force: "gtc"
    }, robinhood_headers)
  end
end
