version 0.2

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

# Using aos for deployment

1. install the DbAdmin package first using apm

```
.editor
.load-blueprint apm
apm.install "@rakis/DbAdmin"
apm.install "@rakis/test-unit"
.done
```

1. run the `yarn run setup_aos_deploy:process` command to modify the dbAdmin import statement before deploying the process.

2. .load /path/to_file/process.js

Note: Do not run the yarn build:process command after running the restore:process command because it is going to replace the import statement for dbAdmin and deployments using aos will fail.

## 🧪 Testing

To run the test suite:

```bash
yarn test:process
```

# Testing using aos

We have a script called test.sh which takes in the Action name and data from data.txt which should be in json format. To run the script with new data you have to modify the data.txt file.

chmod +x test.sh
./test.sh <action>

Example:

./test.sh deposit

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
