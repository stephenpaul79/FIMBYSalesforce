const CATEGORY_ICONS = {
    'Art & Craft Supplies':                'palette.png',
    'Baby & Children':                     'onesie.png',
    'Bikes':                               'bicycle.png',
    'Books':                               'stack-of-books.png',
    'Camping Gear':                        'camping.png',
    'Clothing':                            'male-clothes.png',
    'Electronics':                         'electronic-devices.png',
    'Fitness & Wellness':                  'sport.png',
    'Games & Toys':                        'toys.png',
    'Gardening':                           'gardening.png',
    'Home Improvement & DIY':              'remodeling.png',
    'Household Items':                     'house-cleaning.png',
    'Kitchen Supplies':                    'cookware.png',
    'Music Instruments':                   'music-instrument.png',
    'Office Supplies':                     'stapler.png',
    'Outdoors & Recreation (non-camping)': 'deck-chair.png',
    'Party & Events':                      'party.png',
    'Pet Supplies':                        'pets.png',
    'Photography & AV':                    'music.png',
    'Sports Equipment':                    'sports.png',
    'Tools':                               'tools.png',
    'Travel & Luggage':                    'luggage.png',
    'Other':                               'unknown.png'
};

const CATEGORY_COLORS = {
    'Art & Craft Supplies':                '#7D6234',
    'Baby & Children':                     '#7A5270',
    'Bikes':                               '#357280',
    'Books':                               '#2E4466',
    'Camping Gear':                        '#5A6838',
    'Clothing':                            '#6A5278',
    'Electronics':                         '#4E5E78',
    'Fitness & Wellness':                  '#2A6842',
    'Games & Toys':                        '#885840',
    'Gardening':                           '#3A5C2C',
    'Home Improvement & DIY':              '#8A5936',
    'Household Items':                     '#6B5E50',
    'Kitchen Supplies':                    '#7A4340',
    'Music Instruments':                   '#6E6530',
    'Office Supplies':                     '#4E5858',
    'Outdoors & Recreation (non-camping)': '#2E7460',
    'Party & Events':                      '#7A4A5E',
    'Pet Supplies':                        '#7A4E52',
    'Photography & AV':                    '#44406A',
    'Sports Equipment':                    '#3E6E48',
    'Tools':                               '#555048',
    'Travel & Luggage':                    '#3A5E7A',
    'Other':                               '#736B5C'
};

const DEFAULT_ICON = 'unknown.png';
const DEFAULT_COLOR = '#736B5C';

function getCategoryIconUrl(impactIconsBase, category) {
    const file = CATEGORY_ICONS[category] || DEFAULT_ICON;
    return `${impactIconsBase}/${file}`;
}

function getCategoryStyle(category) {
    const color = CATEGORY_COLORS[category] || DEFAULT_COLOR;
    return `background-color: ${color}; color: #ffffff;`;
}

function getCategoryColor(category) {
    return CATEGORY_COLORS[category] || DEFAULT_COLOR;
}

export {
    CATEGORY_ICONS,
    CATEGORY_COLORS,
    getCategoryIconUrl,
    getCategoryStyle,
    getCategoryColor
};