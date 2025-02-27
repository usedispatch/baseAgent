import { describe, test, before } from "node:test";
import { dryrun, message, createDataItemSigner } from "@permaweb/aoconnect";
const aosConfig = require("/Users/pratik/development/work/usedispatch/amm/arwallet1.json");
// console.log(aosConfig);
const dataItemSigner = createDataItemSigner(aosConfig);

const DCA_PROCESS = "V61ttgXklJOMXR7dJoNI-vs91gLD6VuP_3VE2noOOX0";
const QUOTE_TOKEN_PROCESS = "susX6iEMMuxJSUnVGXaiEu9PwOeFpIwx4mj1k4YiEBk";
const BONDING_CURVE_PROCESS = "KKhElSLcvqeP49R96qXaRokb1bu1qPBKx2MyFsRxIl4";
const to18Decimals = (num: number): string => {
  // Handle negative numbers
  const isNegative = num < 0;
  const absNum = Math.abs(num);

  // Convert to string and split into integer and decimal parts
  const [integerPart, decimalPart = ""] = absNum.toString().split(".");

  // Pad or truncate decimal places to 18
  const paddedDecimal = decimalPart.padEnd(18, "0").slice(0, 18);

  // Combine parts and handle negative numbers
  return `${isNegative ? "-" : ""}${integerPart}${paddedDecimal}`;
};

describe("Tests", () => {
  test("deposit", async () => {
    const res = await message({
      process: QUOTE_TOKEN_PROCESS,
      signer: dataItemSigner,
      tags: [
        {
          name: "Action",
          value: "Transfer",
        },
        {
          name: "Recipient",
          value: DCA_PROCESS,
        },
        { name: "Quantity", value: to18Decimals(1000) },
        {
          name: "X-Action",
          value: "deposit",
        },
        {
          name: "X-Orders",
          value: "2",
        },
        {
          name: "X-Interval",
          value: "36000",
        },
        {
          name: "X-Bonding-Curve",
          value: BONDING_CURVE_PROCESS,
        },
      ],
    });
    console.log("deposit res", res);
  });
  test("getBalance", async () => {
    const res = await dryrun({
      process: DCA_PROCESS,
      tags: [
        {
          name: "Action",
          value: "getBalance",
        },
      ],
    });

    console.log("getBalance res", res.Messages[0]);
  });
  // test("trade", async () => {
  //   const res = await message({
  //     process: DCA_PROCESS,
  //     signer: dataItemSigner,
  //     tags: [
  //       {
  //         name: "Action",
  //         value: "Cron",
  //       },
  //     ],
  //   });
  //   console.log("trade res", res);
  // });
  test("getOrders", async () => {
    const res = await dryrun({
      process: DCA_PROCESS,
      tags: [
        {
          name: "Action",
          value: "getOrders",
        },
      ],
    });
    console.log("getOrders res", res.Messages[0]);
  });
});
