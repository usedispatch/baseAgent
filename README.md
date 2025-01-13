# Trading Agent

A decentralized trading agent built with AO and Lua. This application implements various trading strategies including DCA (Dollar-Cost Averaging) and Value Averaging using AO's permanent computation network.

## 🏗️ Project Structure

- `/process` - AO process (smart contract) code
  - `/src/lib` - Core processing and handler logic
  - `/src/utils` - Trading strategies and utility functions
- `/test` - Test suite for the AO process

## 🚀 Features

- Multiple trading strategies:
  - Dollar-Cost Averaging (DCA)
  - Value Averaging (VA)
- Automated trade execution
- Configurable trading parameters
- Balance and order management
- Decentralized state management via AO

## 📋 Prerequisites

- Node.js (v18 or higher)
- Yarn package manager
- Arweave Wallet (for interacting with AO network)
- Basic understanding of trading strategies

## 🛠️ Trading Strategies

### Dollar-Cost Averaging (DCA)

- Invests fixed amounts at regular intervals
- Configurable investment amount and intervals
- Helps average out purchase prices over time

### Value Averaging (VA)

- Targets specific portfolio value growth
- Dynamically adjusts investment based on market conditions
- Buys more when prices are low, sells when high
- Configurable monthly target increase and investment limits

## 💼 Configuration

Each strategy can be configured through their respective config objects:

```lua
-- Value Averaging Configuration
VA_CONFIG = {
    target_monthly_increase = 1000,  -- Monthly target increase ($)
    max_single_investment = 5000,    -- Maximum single trade
    min_single_investment = 100      -- Minimum trade size
}
```

## 🔧 Installation

1. Clone the repository:

   ```bash
   git clone https://github.com/yourusername/tradeAgent.git
   ```

2. Install dependencies:

   ```bash
   yarn install
   ```

3. Build the AO process:

   ```bash
   yarn build:process
   ```

4. Deploy the AO process:
   ```bash
   yarn deploy:process
   ```

## 🧪 Testing

To run the test suite:

```bash
yarn test:process
```

## 📝 Usage

The trading agent processes trades through message handlers:

- `deposit` - Add funds to trading balance
- `withdraw` - Withdraw funds
- `getDeposit` - Check current balance
- `getOrders` - View order history
- `trade` - Execute trades based on current strategy

## 🤝 Contributing

Contributions are welcome! Feel free to:

- Add new trading strategies
- Improve existing strategies
- Enhance risk management
- Add more test cases

## 📜 License

This project is licensed under the MIT License - see the LICENSE file for details.
