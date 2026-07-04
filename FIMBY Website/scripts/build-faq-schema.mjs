/**
 * Extract FAQ Q&A from faq.html and emit a JSON-LD script block for FAQPage schema.
 * Run: node "FIMBY Website/scripts/build-faq-schema.mjs"
 */
import { readFileSync, writeFileSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const html = readFileSync(join(root, "faq.html"), "utf8");

function stripHtml(s) {
  return s
    .replace(/<script[\s\S]*?<\/script>/gi, "")
    .replace(/<style[\s\S]*?<\/style>/gi, "")
    .replace(/<br\s*\/?>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&mdash;/g, "—")
    .replace(/&rarr;/g, "→")
    .replace(/&amp;/g, "&")
    .replace(/\s+/g, " ")
    .trim();
}

const detailsRe = /<details[^>]*>\s*<summary>([\s\S]*?)<\/summary>\s*<div class="faq-answer"[^>]*>([\s\S]*?)<\/div>\s*<\/details>/gi;
const mainEntity = [];
let m;
while ((m = detailsRe.exec(html)) !== null) {
  const question = stripHtml(m[1]);
  const answer = stripHtml(m[2]);
  if (question && answer) {
    mainEntity.push({
      "@type": "Question",
      name: question,
      acceptedAnswer: {
        "@type": "Answer",
        text: answer,
      },
    });
  }
}

const schema = {
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "@id": "https://fimby.com/faq/#faqpage",
  mainEntity,
};

const script = `<script type="application/ld+json">\n${JSON.stringify(schema, null, 2)}\n</script>`;
writeFileSync(join(root, "seo", "faq-schema.ldjson.html"), script, "utf8");
console.log(`Wrote ${mainEntity.length} FAQ entries to seo/faq-schema.ldjson.html`);
