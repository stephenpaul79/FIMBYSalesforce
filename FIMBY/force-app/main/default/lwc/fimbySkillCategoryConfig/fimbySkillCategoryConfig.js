const CATEGORY_ICONS = {
    'Tutoring & Lessons':           'lessons.png',
    'Language & Translation':       'language.png',
    'Tech Help':                    'tech.png',
    'Skilled Trades':               'trades.png',
    'Home Repairs & Handywork':     'handywork.png',
    'Cleaning & Organizing':        'cleaning.png',
    'Yard & Outdoor Work':          'yardwork.png',
    'Moving & Heavy Lifting':       'moving.png',
    'Rides & Transportation':       'driving.png',
    'Errands & Shopping':           'shopping.png',
    'Cooking & Baking':             'cooking.png',
    'Sewing & Mending':             'sewing.png',
    'Childcare & Babysitting':      'childcare.png',
    'Eldercare & Companionship':    'eldercare.png',
    'Pet Care':                     'petcare.png',
    'Fitness & Wellness':           'fitness.png',
    'Hair & Beauty':                'hair.png',
    'Arts & Crafts':                'crafts.png',
    'Music & Performance':          'musicperformance.png',
    'Event Help':                   'admin.png',
    'Admin & Paperwork':            'paperwork.png',
    'Financial & Tax Help':         'finances.png',
    'Legal Guidance':               'legal.png',
    'Business & Career':            'career.png',
    'Auto & Bike Repair':           'mechanic.png',
    'Other / General Help':         'help.png'
};

const CATEGORY_COLORS = {
    'Tutoring & Lessons':           '#2E4466',
    'Language & Translation':       '#3A5E7A',
    'Tech Help':                    '#4E5E78',
    'Skilled Trades':               '#555048',
    'Home Repairs & Handywork':     '#8A5936',
    'Cleaning & Organizing':        '#6B5E50',
    'Yard & Outdoor Work':          '#3A5C2C',
    'Moving & Heavy Lifting':       '#7A4340',
    'Rides & Transportation':       '#357280',
    'Errands & Shopping':           '#885840',
    'Cooking & Baking':             '#7A4340',
    'Sewing & Mending':             '#6A5278',
    'Childcare & Babysitting':      '#7A5270',
    'Eldercare & Companionship':    '#6E6530',
    'Pet Care':                     '#7A4E52',
    'Fitness & Wellness':           '#2A6842',
    'Hair & Beauty':                '#7A4A5E',
    'Arts & Crafts':                '#7D6234',
    'Music & Performance':          '#44406A',
    'Event Help':                   '#4E5858',
    'Admin & Paperwork':            '#4E5858',
    'Financial & Tax Help':         '#3E6E48',
    'Legal Guidance':               '#2E4466',
    'Business & Career':            '#357280',
    'Auto & Bike Repair':           '#555048',
    'Other / General Help':         '#736B5C'
};

const DEFAULT_ICON = 'help.png';
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
