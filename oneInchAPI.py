import requests
import os
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

API = os.getenv("API_TOKEN")
PSM = "0x17A8541B82BF67e10B0874284b4Ae66858cb1fd5"
USDC = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831"
WETH = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1"
ETH = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
USDT = "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9"
USDCE = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8"

PSM_AMOUNT = 59410765679358251996998  # 59410765679358251996998

method = "get"
apiUrl = "https://api.1inch.dev/swap/v5.2/42161/swap"

requestOptions = {
    "headers": {"Authorization": f"Bearer {API}"},
    "body": {},
    "params": {
        "src": f"{PSM}",
        "dst": f"{ETH}",
        "amount": f"{PSM_AMOUNT}",
        "from": "0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f",
        "slippage": "10",
        "receiver": "0x3440326f551B8A7ee198cEE35cb5D517f2d296a2",
        "disableEstimate": "true",
        "compatibility": "true",
        "protocols": "ARBITRUM_UNISWAP_V3",
    },
}

# Prepare request components
headers = requestOptions.get("headers", {})
body = requestOptions.get("body", {})
params = requestOptions.get("params", {})

response = requests.get(apiUrl, headers=headers, params=params)

# Check if the request was successful (status code 200)
if response.status_code == 200:
    # Parse the JSON response
    json_response = response.json()

    # Access the 'data' field
    data_field = json_response.get("tx").get("data")[10:]

    print(data_field)
else:
    print(f"Request failed with status code {response.json()}")


# if it will be used for converting portal energy to liquidity. minPSM, and minWeth should be added to the end of calldata.
