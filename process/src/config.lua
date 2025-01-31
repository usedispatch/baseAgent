return {
    current_strategy = "dca",
    strategies = {
        dca = {
            investment_amount = 100,
            min_price_change = 0.02,
            max_single_investment = 500
        },
        va = {
            target_monthly_increase = 1000,
            max_single_investment = 5000,
            min_single_investment = 100
        }
    }
} 