#!/usr/bin/env python3
"""
Fix the data mapping in 10_fancy_dashboard.html to match the actual CSV field names
"""

import re

# Read the current dashboard file
with open('3_output/10_fancy_dashboard.html', 'r', encoding='utf-8') as f:
    content = f.read()

# Field name mappings
field_mappings = {
    'country': 'country_name',
    'livability': 'parks_per_100k',
    'forest': 'n_parks',  # This is not ideal but we'll use what we have
    'gdp_per_capita': 'n_parks',  # Placeholder
    'population': 'estimated_population',
    'continent': 'continent',
    'region': 'region',
    'global_rank': 'global_rank',
    'tier': 'tier'
}

# Replace field references in the code
for old_field, new_field in field_mappings.items():
    # Update color mapping function
    if old_field == 'livability':
        content = re.sub(
            r'getCountryColor\(country\.livability\)',
            f'getCountryColor(country.parks_per_100k)',
            content
        )

    # Update chart data
    if old_field == 'livability':
        content = re.sub(
            r'country\.livability',
            'country.parks_per_100k',
            content
        )

    # Update table displays
    if old_field == 'livability':
        content = re.sub(
            r'country\.livability_index\s*\|\s*country\.livability',
            'country.parks_per_100k',
            content
        )

# Update the forest vs GDP chart since we don't have forest data
# We'll use parks_per_100k for both axes as a placeholder
content = re.sub(
    r'parseFloat\(country\.forest_cover\|country\.forest\)',
    'country.parks_per_100k',
    content
)

# Write the fixed file
with open('3_output/10_fancy_dashboard_fixed.html', 'w', encoding='utf-8') as f:
    f.write(content)

print("Fixed dashboard saved as 3_output/10_fancy_dashboard_fixed.html")
print("Please use this file instead of the original one.")
print("\nTo use it:")
print("1. Use VS Code Live Server to open 3_output/10_fancy_dashboard_fixed.html")
print("2. Or run: python serve_dashboard.py")
print("3. Then visit: http://localhost:8000/3_output/10_fancy_dashboard_fixed.html")