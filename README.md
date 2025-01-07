# AO App Template

A full-stack decentralized counter application built with AO, React, TypeScript, and Vite. This application demonstrates a simple counter implementation using AO's permanent computation network.

## 🏗️ Project Structure

- `/app` - Frontend React application
- `/process` - AO process (smart contract) code
- `/test` - Test suite for the AO process

## 🚀 Features

- Increment/decrement counter functionality
- Decentralized state management via AO
- Full test coverage
- TypeScript support
- Modern React with Vite

## 📋 Prerequisites

- Node.js (v18 or higher)
- Yarn package manager
- Arweave Wallet (for interacting with AO network)

## 🛠️ Installation

1. Clone the repository:

   ```bash
   git clone https://github.com/permaweb/ao-counter-app.git
   ```

2. Install dependencies:

   ```bash
   yarn install
   cd app && yarn install
   cd test && yarn install
   ```

3. Build the AO process:

   ```bash
   yarn build:process
   ```

4. Deploy the AO process:

   ```bash
   yarn deploy:process
   ```

5. Run the frontend:

   ```bash
   yarn dev:frontend
   ```

## 🧪 Testing

To run the test suite for the AO process:

```bash
yarn test:process
```
