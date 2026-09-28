/**
 * @description Category icon + badge colour lookup for library items and skill offers in
 * emails. Mirrors c/fimbyLibraryCategoryConfig and c/fimbySkillCategoryConfig so email
 * badges match the Library tab — keep all four maps in sync with those LWC configs.
 */
public inherited sharing class FimbyLibraryCategoryStyle {

    private static final String ITEM_DEFAULT_ICON = 'unknown.png';
    private static final String SKILL_DEFAULT_ICON = 'help.png';
    private static final String DEFAULT_COLOR = '#736B5C';

    private static final Map<String, String> ITEM_ICONS = new Map<String, String>{
        'Art & Craft Supplies' => 'palette.png', 'Baby & Children' => 'onesie.png',
        'Bikes' => 'bicycle.png', 'Books' => 'stack-of-books.png',
        'Camping Gear' => 'camping.png', 'Clothing' => 'male-clothes.png',
        'Electronics' => 'electronic-devices.png', 'Fitness & Wellness' => 'sport.png',
        'Games & Toys' => 'toys.png', 'Gardening' => 'gardening.png',
        'Home Improvement & DIY' => 'remodeling.png', 'Household Items' => 'house-cleaning.png',
        'Kitchen Supplies' => 'cookware.png', 'Music Instruments' => 'music-instrument.png',
        'Office Supplies' => 'stapler.png', 'Outdoors & Recreation (non-camping)' => 'deck-chair.png',
        'Party & Events' => 'party.png', 'Pet Supplies' => 'pets.png',
        'Photography & AV' => 'music.png', 'Sports Equipment' => 'sports.png',
        'Tools' => 'tools.png', 'Travel & Luggage' => 'luggage.png', 'Other' => 'unknown.png'
    };

    private static final Map<String, String> ITEM_COLORS = new Map<String, String>{
        'Art & Craft Supplies' => '#7D6234', 'Baby & Children' => '#7A5270',
        'Bikes' => '#357280', 'Books' => '#2E4466',
        'Camping Gear' => '#5A6838', 'Clothing' => '#6A5278',
        'Electronics' => '#4E5E78', 'Fitness & Wellness' => '#2A6842',
        'Games & Toys' => '#885840', 'Gardening' => '#3A5C2C',
        'Home Improvement & DIY' => '#8A5936', 'Household Items' => '#6B5E50',
        'Kitchen Supplies' => '#7A4340', 'Music Instruments' => '#6E6530',
        'Office Supplies' => '#4E5858', 'Outdoors & Recreation (non-camping)' => '#2E7460',
        'Party & Events' => '#7A4A5E', 'Pet Supplies' => '#7A4E52',
        'Photography & AV' => '#44406A', 'Sports Equipment' => '#3E6E48',
        'Tools' => '#555048', 'Travel & Luggage' => '#3A5E7A', 'Other' => '#736B5C'
    };

    private static final Map<String, String> SKILL_ICONS = new Map<String, String>{
        'Tutoring & Lessons' => 'lessons.png', 'Language & Translation' => 'language.png',
        'Tech Help' => 'tech.png', 'Skilled Trades' => 'trades.png',
        'Home Repairs & Handywork' => 'handywork.png', 'Cleaning & Organizing' => 'cleaning.png',
        'Yard & Outdoor Work' => 'yardwork.png', 'Moving & Heavy Lifting' => 'moving.png',
        'Rides & Transportation' => 'driving.png', 'Errands & Shopping' => 'shopping.png',
        'Cooking & Baking' => 'cooking.png', 'Sewing & Mending' => 'sewing.png',
        'Childcare & Babysitting' => 'childcare.png', 'Eldercare & Companionship' => 'eldercare.png',
        'Pet Care' => 'petcare.png', 'Fitness & Wellness' => 'fitness.png',
        'Hair & Beauty' => 'hair.png', 'Arts & Crafts' => 'crafts.png',
        'Music & Performance' => 'musicperformance.png', 'Event Help' => 'admin.png',
        'Admin & Paperwork' => 'paperwork.png', 'Financial & Tax Help' => 'finances.png',
        'Legal Guidance' => 'legal.png', 'Business & Career' => 'career.png',
        'Auto & Bike Repair' => 'mechanic.png', 'Other / General Help' => 'help.png'
    };

    private static final Map<String, String> SKILL_COLORS = new Map<String, String>{
        'Tutoring & Lessons' => '#2E4466', 'Language & Translation' => '#3A5E7A',
        'Tech Help' => '#4E5E78', 'Skilled Trades' => '#555048',
        'Home Repairs & Handywork' => '#8A5936', 'Cleaning & Organizing' => '#6B5E50',
        'Yard & Outdoor Work' => '#3A5C2C', 'Moving & Heavy Lifting' => '#7A4340',
        'Rides & Transportation' => '#357280', 'Errands & Shopping' => '#885840',
        'Cooking & Baking' => '#7A4340', 'Sewing & Mending' => '#6A5278',
        'Childcare & Babysitting' => '#7A5270', 'Eldercare & Companionship' => '#6E6530',
        'Pet Care' => '#7A4E52', 'Fitness & Wellness' => '#2A6842',
        'Hair & Beauty' => '#7A4A5E', 'Arts & Crafts' => '#7D6234',
        'Music & Performance' => '#44406A', 'Event Help' => '#4E5858',
        'Admin & Paperwork' => '#4E5858', 'Financial & Tax Help' => '#3E6E48',
        'Legal Guidance' => '#2E4466', 'Business & Career' => '#357280',
        'Auto & Bike Repair' => '#555048', 'Other / General Help' => '#736B5C'
    };

    public static String itemIcon(String category) {
        return lookup(ITEM_ICONS, category, ITEM_DEFAULT_ICON);
    }

    public static String itemColor(String category) {
        return lookup(ITEM_COLORS, category, DEFAULT_COLOR);
    }

    public static String skillIcon(String category) {
        return lookup(SKILL_ICONS, category, SKILL_DEFAULT_ICON);
    }

    public static String skillColor(String category) {
        return lookup(SKILL_COLORS, category, DEFAULT_COLOR);
    }

    private static String lookup(Map<String, String> source, String category, String fallback) {
        return String.isNotBlank(category) && source.containsKey(category) ? source.get(category) : fallback;
    }
}
