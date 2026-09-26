import fs from 'fs';
import path from 'path';

const lwcRoot = path.join(
    'c:/Users/srathjen/FIMBY/FIMBY/force-app/main/default/lwc'
);

const IMPORT = "import { createShellScrimHandle } from 'c/fimbyModalShell';";
const FIELD = '    _shellScrim = createShellScrimHandle();';

const bundles = [
    'fimbyQuickResponseModal',
    'fimbyReportContent',
    'fimbySubmitFeedback',
    'fimbyThanksGiving',
    'fimbyResponseReply',
    'fimbyResponseStatusUpdate',
    'fimbyPostEditModal',
    'fimbyRecordEditModal',
    'fimbyVouchRevokeModal',
    'fimbyVouchDeclineModal',
    'fimbyVouchingRequiredModal',
    'fimbyIntroPostModal',
    'fimbyLendingApprovalModal',
    'fimbyLendingConfirmationModal',
    'fimbyLoanExtensionModal',
    'fimbyLoanExtensionApprovalModal',
    'fimbyBulkBuyPickupModal',
    'fimbyNotRespondingModal',
    'fimbySkillEditModal',
    'fimbyPickupConfirmationModal',
    'fimbyItemReturnModal',
    'fimbyModeratorTaskModalShell',
    'fimbyOnboardingModal',
    'fimbyFamilyMemberSetupModal',
    'fimbyRelationshipSetupModal',
    'fimbyImageCropper'
];

function patchFile(bundle) {
    const jsPath = path.join(lwcRoot, bundle, `${bundle}.js`);
    if (!fs.existsSync(jsPath)) {
        console.log('skip missing', bundle);
        return;
    }
    let src = fs.readFileSync(jsPath, 'utf8');
    if (src.includes('createShellScrimHandle')) {
        console.log('skip wired', bundle);
        return;
    }
    if (!src.includes('@api') || !src.includes('hide(')) {
        console.log('skip no hide', bundle);
        return;
    }

    const importIdx = src.lastIndexOf('\nimport ');
    if (importIdx === -1) {
        console.log('skip no import', bundle);
        return;
    }
    const endImportLine = src.indexOf('\n', importIdx + 1);
    const nextChunk = src.slice(endImportLine + 1, endImportLine + 80);
    if (!nextChunk.startsWith('import ') && !nextChunk.startsWith('const ')) {
        src =
            src.slice(0, endImportLine + 1) +
            IMPORT +
            '\n' +
            src.slice(endImportLine + 1);
    } else {
        let pos = endImportLine;
        while (true) {
            const lineEnd = src.indexOf('\n', pos + 1);
            const line = src.slice(pos + 1, lineEnd);
            if (
                line.startsWith('import ') ||
                line.startsWith('const TYPE_') ||
                line.trim() === ''
            ) {
                pos = lineEnd;
                continue;
            }
            src = src.slice(0, pos + 1) + IMPORT + '\n' + src.slice(pos + 1);
            break;
        }
    }

    const classMatch = src.match(
        /export default class \w+ extends [\s\S]*?\{/
    );
    if (!classMatch) {
        console.log('skip no class', bundle);
        return;
    }
    const insertAt = classMatch.index + classMatch[0].length;
    src = src.slice(0, insertAt) + '\n' + FIELD + src.slice(insertAt);

    src = src.replace(
        /(@api\s*\n\s*hide\s*\([^)]*\)\s*\{)/,
        '$1\n        this._shellScrim.clear();'
    );

    const showRe = /@api\s*\n\s*(?:async\s+)?show\s*\([^)]*\)\s*\{/g;
    let showMatch;
    let lastShowEnd = -1;
    while ((showMatch = showRe.exec(src)) !== null) {
        lastShowEnd = showMatch.index + showMatch[0].length;
    }
    if (lastShowEnd === -1) {
        console.log('skip no show', bundle);
        return;
    }

    const afterShow = src.slice(lastShowEnd);
    const visMatch = afterShow.match(
        /\n(\s*)(this\.(?:_\w+Visible|showModal|isVisible)\s*=\s*true;)/
    );
    if (!visMatch) {
        console.log('skip no visible assign', bundle);
        return;
    }
    const bindLine = `\n${visMatch[1]}this._shellScrim.bind(() => this.hide());`;
    const absIdx = lastShowEnd + visMatch.index + visMatch[0].length;
    src = src.slice(0, absIdx) + bindLine + src.slice(absIdx);

    if (src.includes('disconnectedCallback')) {
        src = src.replace(
            /(disconnectedCallback\s*\(\)\s*\{)/,
            '$1\n        this._shellScrim.clear();'
        );
    }

    fs.writeFileSync(jsPath, src);
    console.log('patched', bundle);
}

for (const b of bundles) {
    patchFile(b);
}
