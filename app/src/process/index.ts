import { dryrun, message, createDataItemSigner } from "@permaweb/aoconnect";

const process = "ycnYNvOkTPSp5XqUq6K_jiAFt4XDs47qKjSE_sLde0k";

type Tags =
  | {
      name: string;
      value: string;
    }[]
  | undefined;

export async function sendAOMessage(tags: Tags, data?: string) {
  try {
    const signer = createDataItemSigner((globalThis as any).arweaveWallet);
    const res = await message({
      process,
      signer,
      tags,
      data,
    });
    console.log("Result of sending message", res);
    return res;
  } catch (error) {
    console.error("Error sending message", error);
  }
}

export async function incrementCounter() {
  try {
    const incrementCounterResponse = await sendAOMessage([
      {
        name: "Action",
        value: "incrementCounter",
      },
    ]);
    console.log("Increment counter response", incrementCounterResponse);
    return incrementCounterResponse;
  } catch (error) {
    console.error("Error incrementing counter", error);
  }
}

export async function decrementCounter() {
  try {
    const decrementCounterResponse = await sendAOMessage([
      {
        name: "Action",
        value: "decrementCounter",
      },
    ]);
    console.log("Decrement counter response", decrementCounterResponse);
    return decrementCounterResponse;
  } catch (error) {
    console.error("Error decrementing counter", error);
  }
}

export async function getCounter() {
  try {
    const result = await dryrun({
      process,
      tags: [
        {
          name: "Action",
          value: "getCounter",
        },
      ],
    });
    console.log("getCounter result", result);
    return JSON.parse(result.Messages[0].Data);
  } catch (error) {
    console.error("Error getting counter", error);
  }
}

export async function connectArConnectWallet() {
  try {
    // connect to the ArConnect browser extension
    await (globalThis as any).arweaveWallet.connect(
      // request permissions
      ["ACCESS_ADDRESS", "SIGN_TRANSACTION"]
    );
  } catch (error) {
    alert("You should connect to ArConnect browser extension.");
    console.error(error);
    return false;
  }

  return true;
}

export async function getWalletAddress() {
  let address;
  try {
    address = await (globalThis as any).arweaveWallet.getActiveAddress();
  } catch (error) {
    console.error(error);
    return localStorage.getItem("owner");
  }

  return address;
}
