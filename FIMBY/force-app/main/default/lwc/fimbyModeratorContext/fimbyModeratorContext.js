import getModeratorHeaderData from '@salesforce/apex/FimbyModeratorDashboardController.getModeratorHeaderData';

let _cachedResult = null;
let _fetchPromise = null;

export async function getModeratorContext() {
    if (_cachedResult) return _cachedResult;
    if (_fetchPromise) return _fetchPromise;
    _fetchPromise = getModeratorHeaderData()
        .then(result => {
            _cachedResult = {
                isModerator: result.isModerator || false,
                taskCount: result.taskCount || 0,
                neighbourhoodNames: result.neighbourhoodNames || []
            };
            return _cachedResult;
        })
        .catch(() => {
            _cachedResult = { isModerator: false, taskCount: 0, neighbourhoodNames: [] };
            return _cachedResult;
        });
    return _fetchPromise;
}

export function invalidateModeratorContext() {
    _cachedResult = null;
    _fetchPromise = null;
}