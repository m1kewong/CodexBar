import asyncio
from playwright.async_api import async_playwright
import json
import sys
import os
import argparse

class EPRCScraper:
    def __init__(self, username, password, corporate_code=None):
        self.username = username
        self.password = password
        self.corporate_code = corporate_code
        self.base_url = 'https://www.eprc.com.hk'
        
    async def run(self, months=2, district='HK-P', usage='RES', output_file=None):
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            context = await browser.new_context(
                user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36'
            )
            page = await context.new_page()
            
            print(f"Logging in as {self.username}...")
            await page.goto(f"{self.base_url}/EprcWeb/multi/transaction/login.do")
            
            # Fill login form
            await page.fill('#userName', self.username)
            # Trigger blur to activate checkUser
            await page.evaluate('document.getElementById("userName").blur()')
            await page.wait_for_timeout(1000)
            
            await page.fill('#password', self.password)
            if self.corporate_code:
                # Need to wait for corporate code field to appear
                try:
                    await page.wait_for_selector('#corporateCode', state='visible', timeout=3000)
                    await page.fill('#corporateCode', self.corporate_code)
                except:
                    # Force the field to be visible and loginType to cop
                    await page.evaluate('''
                        document.getElementById("corporateCode").style.display = "block";
                        document.getElementById("loginType").value = "cop";
                    ''')
                    await page.fill('#corporateCode', self.corporate_code)
            
            # Click login and wait for navigation or dialog
            try:
                async with page.expect_navigation(timeout=5000):
                    await page.click('a.btn.btn-primary')
            except:
                pass # Might not navigate if dialog appears
                
            await page.wait_for_timeout(2000)
            
            # Handle concurrent login if needed
            try:
                dialog_visible = await page.evaluate('document.getElementById("loginRequestMessage") !== null && document.getElementById("loginRequestMessage").style.display !== "none"')
                if dialog_visible:
                    print("Concurrent login detected, forcing login...")
                    # Click the Send Request button
                    await page.click('#loginRequestSendRequestButton')
                    
                    # Wait for the force login to complete
                    try:
                        async with page.expect_navigation(timeout=35000): # Wait up to 35s since the JS has a 30s timeout
                            pass
                    except:
                        pass
                    await page.wait_for_timeout(3000)
                    
                    # If we are still on the login page, try submitting the form again
                    if "login.do" in page.url:
                        print("Still on login page, submitting form again...")
                        try:
                            async with page.expect_navigation(timeout=5000):
                                await page.evaluate('document.getElementById("LoginForm").submit()')
                        except:
                            pass
                        await page.wait_for_timeout(3000)
            except Exception as e:
                print(f"Dialog check error: {e}")
                
            # Check if login successful
            try:
                is_logged_in = await page.evaluate("document.querySelector('.menu') !== null || document.body.innerHTML.indexOf('註冊成交') !== -1")
                if not is_logged_in:
                    print("Login failed or still waiting for concurrent login resolution.")
                    await page.screenshot(path='login_failed.png')
                    await browser.close()
                    return None
            except Exception as e:
                print(f"Error checking login status: {e}")
                await page.screenshot(path='login_failed.png')
                await browser.close()
                return None
                
            print("Login successful!")
            
            # Navigate to search page
            print(f"Searching transactions for district {district}, past {months} months...")
            
            # Get the iframe
            iframe_element = await page.wait_for_selector('#iframe_content')
            frame = await iframe_element.content_frame()
            
            # Fill search form
            await frame.select_option('#dateRange', str(months))
            await frame.select_option('#usage', usage)
            await frame.select_option('#district', district)
            
            # Click search
            await frame.click('#submitButton')
            
            # Wait for results to load
            await page.wait_for_timeout(5000)
            
            # Wait for the results table to appear
            try:
                await frame.wait_for_selector('table.resultTable', timeout=10000)
            except:
                print("Results table not found. Taking screenshot...")
                await page.screenshot(path='search_failed.png')
            
            # Extract results
            results = await frame.evaluate('''() => {
                var rows = document.querySelectorAll('table.resultTable tr');
                var data = [];
                rows.forEach(function(row) {
                    var cells = row.querySelectorAll('td');
                    if (cells.length >= 10) {
                        var text = row.textContent.replace(/\\s+/g, ' ').trim();
                        if ((text.indexOf('RES') !== -1 || text.indexOf('住宅') !== -1) && 
                            (text.indexOf('ASP') !== -1 || text.indexOf('合約') !== -1)) {
                            
                            var c = Array.from(cells).map(cell => cell.textContent.trim().replace(/\\u00a0/g, ' '));
                            
                            // Find building cell
                            var b_idx = -1;
                            for (var i = 0; i < cells.length; i++) {
                                if (cells[i].querySelector('a') && 
                                    (cells[i].textContent.indexOf('BLK') !== -1 || 
                                     cells[i].textContent.indexOf('TWR') !== -1 || 
                                     cells[i].textContent.indexOf('座') !== -1 || 
                                     cells[i].textContent.indexOf('苑') !== -1 || 
                                     cells[i].textContent.indexOf('大廈') !== -1 ||
                                     (i > 0 && c[i-1].indexOf('RES') !== -1))) {
                                    b_idx = i;
                                    break;
                                }
                            }
                            
                            if (b_idx === -1) {
                                for (var i = 0; i < c.length; i++) {
                                    if (c[i].indexOf('RES') !== -1 || c[i].indexOf('住宅') !== -1) {
                                        b_idx = i + 1;
                                        break;
                                    }
                                }
                            }
                            
                            if (b_idx !== -1 && b_idx < c.length) {
                                data.push({
                                    'usage': b_idx > 0 ? c[b_idx-1] : '',
                                    'building': c[b_idx],
                                    'instrument_date': b_idx+1 < c.length ? c[b_idx+1] : '',
                                    'floor': b_idx+2 < c.length ? c[b_idx+2] : '',
                                    'unit': b_idx+3 < c.length ? c[b_idx+3] : '',
                                    'area_gross': b_idx+4 < c.length ? c[b_idx+4] : '',
                                    'area_net': b_idx+5 < c.length ? c[b_idx+5] : '',
                                    'efficiency': b_idx+6 < c.length ? c[b_idx+6] : '',
                                    'price_m': b_idx+7 < c.length ? c[b_idx+7] : '',
                                    'price_sqft_gross': b_idx+8 < c.length ? c[b_idx+8] : '',
                                    'price_sqft_net': b_idx+9 < c.length ? c[b_idx+9] : '',
                                    'nature': b_idx+10 < c.length ? c[b_idx+10] : '',
                                    'delivery_date': b_idx+11 < c.length ? c[b_idx+11] : ''
                                });
                            }
                        }
                    }
                });
                return data;
            }''')
            
            await browser.close()
            
            if output_file and results:
                with open(output_file, 'w', encoding='utf-8') as f:
                    json.dump(results, f, ensure_ascii=False, indent=2)
                print(f"Results saved to {output_file}")
                
            return results

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='EPRC Transaction Scraper')
    parser.add_argument('--username', required=True, help='EPRC username')
    parser.add_argument('--password', required=True, help='EPRC password')
    parser.add_argument('--corp-code', help='EPRC corporate code (if applicable)')
    parser.add_argument('--months', type=int, default=2, help='Number of months to search (default: 2)')
    parser.add_argument('--district', default='HK-P', help='District code (default: HK-P)')
    parser.add_argument('--usage', default='RES', help='Usage code (default: RES)')
    parser.add_argument('--output', help='Output JSON file path')
    
    args = parser.parse_args()
    
    scraper = EPRCScraper(args.username, args.password, args.corp_code)
    results = asyncio.run(scraper.run(
        months=args.months, 
        district=args.district, 
        usage=args.usage,
        output_file=args.output
    ))
    
    if results:
        print(f"\nFound {len(results)} transactions.")
        if not args.output:
            print(json.dumps(results[:3], indent=2, ensure_ascii=False))
            if len(results) > 3:
                print(f"... and {len(results)-3} more")
