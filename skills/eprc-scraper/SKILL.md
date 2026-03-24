# EPRC Transaction Scraper

This skill provides a robust Python scraper for the EPRC (Economic Property Research Centre) website, allowing you to extract property transaction data.

## Features

- Handles complex login flows, including corporate code authentication
- Automatically resolves "concurrent login" (另一個用戶正在使用中) dialogs by forcing login
- Uses Playwright to navigate the site's iframe-based architecture
- Extracts detailed transaction records including building name, price, area, and dates
- Outputs data in structured JSON format

## Prerequisites

The scraper requires Playwright to be installed:

```bash
pip3 install playwright
playwright install chromium
```

## Usage

You can run the scraper directly from the command line:

```bash
python3 /home/ubuntu/skills/eprc-scraper/eprc_scraper.py --username <USERNAME> --password <PASSWORD> [--corp-code <CORP_CODE>] [--months <MONTHS>] [--district <DISTRICT>] [--usage <USAGE>] [--output <OUTPUT_FILE>]
```

### Arguments

- `--username`: Your EPRC username (Required)
- `--password`: Your EPRC password (Required)
- `--corp-code`: Your EPRC corporate code (Optional, required for corporate accounts)
- `--months`: Number of months to search back (Default: 2)
- `--district`: District code to search (Default: HK-P for Hong Kong Island Peak)
- `--usage`: Property usage type (Default: RES for Residential)
- `--output`: Path to save the results as a JSON file (Optional)

### Example

```bash
python3 /home/ubuntu/skills/eprc-scraper/eprc_scraper.py --username rpro.005 --password mypassword --corp-code e097 --months 3 --district HK-P --output results.json
```

## Output Format

The scraper returns a list of dictionaries, each representing a transaction record with the following fields:

- `usage`: Property usage (e.g., "住宅RES")
- `building`: Building name
- `instrument_date`: Date of the instrument (dd/mm/yyyy)
- `floor`: Floor number
- `unit`: Unit number
- `area_gross`: Gross floor area
- `area_net`: Net floor area
- `efficiency`: Efficiency ratio
- `price_m`: Price in millions
- `price_sqft_gross`: Price per square foot (Gross)
- `price_sqft_net`: Price per square foot (Net)
- `nature`: Transaction nature (e.g., "買賣合約 / ASP")
- `delivery_date`: Delivery date (dd/mm/yyyy)

## Notes for Agents

When using this skill to fulfill user requests:
1. Ensure Playwright is installed in the environment before running the script.
2. The scraper runs in headless mode and handles the complex iframe structure of the EPRC site.
3. The site has a strict concurrent login policy. The scraper is designed to handle the "force login" dialog automatically, but this process takes about 35 seconds to complete.
4. If the user doesn't specify a district, default to `HK-P` (Peak) or ask for clarification.
5. Always save the output to a JSON file using the `--output` flag so you can easily read and process the results.
