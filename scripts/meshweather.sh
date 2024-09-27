#!/bin/sh

# Fetch the weather forecast (change url to desired location)
API_URL="https://api.weather.gov/gridpoints/GRR/38,56/forecast"
FORECAST_JSON=$(curl -s "$API_URL")

# Extract tonight and tomorrow forecasts using indices [0] and [1]
TONIGHT_NAME=$(echo "$FORECAST_JSON" | jq -r '.properties.periods[0].name')
TONIGHT_FORECAST=$(echo "$FORECAST_JSON" | jq -r '.properties.periods[0] | "\(.shortForecast) at \(.temperature)F"')

TOMORROW_NAME=$(echo "$FORECAST_JSON" | jq -r '.properties.periods[1].name')
TOMORROW_FORECAST=$(echo "$FORECAST_JSON" | jq -r '.properties.periods[1] | "\(.shortForecast) at \(.temperature)F"')

# Combine the forecasts
SUMMARY="$TONIGHT_NAME: $TONIGHT_FORECAST. $TOMORROW_NAME: $TOMORROW_FORECAST."

# Truncate to 150 characters if necessary & send weather forecast to mesh
meshtastic --host localhost --sendtext "$SUMMARY" | cut -c 1-150
