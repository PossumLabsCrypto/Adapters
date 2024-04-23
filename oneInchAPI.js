// curl version 
// curl -X GET \
//       "https://api.1inch.dev/swap/v6.0/42161/swap?src=0x17A8541B82BF67e10B0874284b4Ae66858cb1fd5&compatibility=true&disableEstimate=true&allowPartialFill=false&usePermit2=false&slippage=5&from=0xD59Eb7E224Ad741C06c26d4670Fc0C2D89121DE3&dst=0x82aF49447D8a07e3bd95BD0d56f35241523fBab1&amount=25000000000000000000000&receiver=0xB9927a561527Ac7Bb7a93cDc80ba3c7F14EBDD1e&" \
//       -H "Authorization: Bearer oESfoRrx7Qu0xEWUf3M9WCs7oRRYsrap" \
//       -H "accept: application/json" \
//       -H "content-type: application/json" \


// you just need to change 
// slippage
// from: contract address
// dst: to token
// amount (for adding liquidity call just divide amount by 2)
// receiver


// for node js type
// first, install node
// then, npm install axios
// then, npm install dotenv (see .envExample for creating .env file)
// then, node file.js


const dotenv = require('dotenv');
dotenv.config();
const axios = require("axios");

async function httpCall() {

    const url = "https://api.1inch.dev/swap/v6.0/42161/swap";

    const config = {
        headers: {
            "Authorization": `Bearer ${process.env.API_TOKEN}`
        },
        params: {
            "src": "0x17A8541B82BF67e10B0874284b4Ae66858cb1fd5",
            "dst": "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
            "amount": "25000000000000000000000",
            "from": "0x35f0DB0b238D3d0653d75FB67Cd64eE65C32DeFc",
            "slippage": "1",
            "receiver": "0x35f0DB0b238D3d0653d75FB67Cd64eE65C32DeFc",
            "allowPartialFill": "false",
            "disableEstimate": "true",
            "usePermit2": "false",
            "compatibility": "true"
        }
    };


    try {
        const response = await axios.get(url, config);
        // Extract tx from response
        const txData = response.data.tx.data;
        const cutData = "0x" + txData.substring(10);
        console.log(cutData);
    } catch (error) {
        console.error(error);
    }
}

httpCall()




