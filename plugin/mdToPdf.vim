" Define plugin default values, if not re-defined by user
if !exists("g:vim_mdtopdf_cssurl")
    let g:vim_mdtopdf_cssurl = "'". shellescape("file://". expand('<sfile>:p:h:h'). "/". "style/md-style.css"). "'"
endif

if !exists("g:vim_mdtopdf_mermaid")
    let g:vim_mdtopdf_mermaid = 1
endif

if !exists("g:vim_mdtopdf_mermaid_url")
    let g:vim_mdtopdf_mermaid_url = "https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"
endif

let s:vim_mdtopdf_html_includes_path = "'". shellescape("file://". expand('<sfile>:p:h:h'). "/". "html-includes/includes.html"). "'"
let s:vim_mdtopdf_root = expand('<sfile>:p:h:h')

function! s:Progress(step, msg)
    let l:total = 3
    let l:width = 20
    let l:filled = float2nr(round(l:width * a:step / l:total))
    let l:arrow = a:step < l:total ? '>' : '='
    let l:bar = '[' . repeat('=', max([l:filled - 1, 0])) . l:arrow . repeat(' ', l:width - l:filled) . ']'
    let l:pct = printf('%3d%%', float2nr(round(100.0 * a:step / l:total)))
    redraw
    echo l:bar . ' ' . l:pct . ' ' . a:msg
endfunction

function! s:BuildIncludesFile()
    let l:template_path = s:vim_mdtopdf_root . '/html-includes/includes.html'
    let l:content = join(readfile(l:template_path), "\n")

    if g:vim_mdtopdf_mermaid
        let l:mermaid_block = join([
            \ '<script src="' . g:vim_mdtopdf_mermaid_url . '"></script>',
            \ '<script>',
            \ '    var mermaid_complete = false;',
            \ '    (function() {',
            \ '        function finish() {',
            \ '            mermaid_complete = true;',
            \ '        }',
            \ '        function decodeEntities(encoded) {',
            \ '            var textarea = document.createElement("textarea");',
            \ '            textarea.innerHTML = encoded;',
            \ '            return textarea.value;',
            \ '        }',
            \ '        function runMermaid() {',
            \ '            var nodes = Array.prototype.slice.call(document.querySelectorAll(".mermaid"))',
            \ '                .filter(function(el) {',
            \ '                    return !el.parentElement || !el.parentElement.closest(".mermaid");',
            \ '                });',
            \ '            if (nodes.length === 0) {',
            \ '                finish();',
            \ '                return;',
            \ '            }',
            \ '            if (typeof mermaid === "undefined" || !mermaid.run) {',
            \ '                console.error("Mermaid library failed to load");',
            \ '                finish();',
            \ '                return;',
            \ '            }',
            \ '            // Pandoc HTML-escapes characters like > inside code blocks, so decode',
            \ '            // the diagram source before Mermaid parses it. Replace the <pre> wrapper',
            \ '            // with a <div> so the diagram is not styled as a code block, and assign',
            \ '            // IDs so the Python side can screenshot each diagram in document order.',
            \ '            var renderNodes = [];',
            \ '            nodes.forEach(function(el, i) {',
            \ '                var code = el.querySelector("code");',
            \ '                var source = code ? decodeEntities(code.innerHTML) : decodeEntities(el.innerHTML);',
            \ '                var div = document.createElement("div");',
            \ '                div.className = "mermaid";',
            \ '                div.id = "mermaid-png-" + i;',
            \ '                div.textContent = source;',
            \ '                el.parentNode.replaceChild(div, el);',
            \ '                renderNodes.push(div);',
            \ '            });',
            \ '            mermaid.initialize({ startOnLoad: false });',
            \ '            mermaid.run({ nodes: renderNodes, suppressErrors: true }).then(finish).catch(function(err) {',
            \ '                console.error("Mermaid rendering failed:", err);',
            \ '                finish();',
            \ '            });',
            \ '        }',
            \ '        if (document.readyState === "loading") {',
            \ '            document.addEventListener("DOMContentLoaded", runMermaid);',
            \ '        } else {',
            \ '            runMermaid();',
            \ '        }',
            \ '    })();',
            \ '</script>'
            \ ], "\n")
    else
        let l:mermaid_block = '<script>var mermaid_complete = true;</script>'
    endif

    let l:content = substitute(l:content, '{{MERMAID_BLOCK}}', l:mermaid_block, 'g')

    let l:temp_path = tempname() . '.html'
    call writefile(split(l:content, "\n", 1), l:temp_path)
    return l:temp_path
endfunction

function! MdToPdf()
    " Check that Vim has been compiled with python3 support
    if !has('python3')
        echo "Error: Required vim compiled with +python3"
        finish
    endif

    " Build a temporary HTML includes file so Mermaid support can be toggled
    let s:temp_includes_path = s:BuildIncludesFile()

    " Convert the markdown + math to html with pandoc
    lcd %:p:h
    call s:Progress(1, 'Converting Markdown to HTML...')
    let s:pandoc_cmd = "pandoc"
        \ . " -f gfm"
        \ . " --standalone"
        \ . " --css " . g:vim_mdtopdf_cssurl
        \ . " -H " . "'" . shellescape("file://" . s:temp_includes_path) . "'"
        \ . " -o " . shellescape(expand("%:r") . ".html")
        \ . " " . shellescape(expand("%:p"))
    let s:pandoc_out = system(s:pandoc_cmd)
    if v:shell_error
        echoerr "MdToPdf: pandoc failed: " . s:pandoc_out
        finish
    endif

    " Use playwright to render the TeX math using MathJax and Mermaid diagrams, then convert the rendered HTML to a PDF
python3 << EOF
import sys, glob, os
_venv_packages = glob.glob(os.path.join(vim.eval("s:vim_mdtopdf_root"), ".venv", "lib", "python*", "site-packages"))
if _venv_packages:
    sys.path.insert(0, _venv_packages[0])
from base64 import b64encode
from lxml import etree
import os
import vim
from weasyprint import HTML
from playwright.sync_api import sync_playwright

html_path = "file://" + vim.eval("expand('%:p:r')") + ".html"
pdf_path = vim.eval("expand('%:p:r')") + ".pdf"
base_url = vim.eval("expand('%:p:h')")

vim.command("call s:Progress(2, 'Rendering math and diagrams...')")
with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page()
    page.goto(html_path)
    page.wait_for_function('mathjax_complete === true && mermaid_complete === true', timeout=60000)

    # Mermaid renders diagrams using HTML foreignObjects for some node labels.
    # WeasyPrint cannot render those when the SVG is embedded as a data URI, so
    # screenshot each rendered Mermaid diagram and embed the PNG instead.
    mermaid_images = []
    mermaid_count = page.evaluate('''() => {
        return Array.from(document.querySelectorAll('.mermaid'))
            .filter(function(el) {
                return !el.parentElement || !el.parentElement.closest('.mermaid');
            }).length;
    }''')
    for i in range(mermaid_count):
        el = page.query_selector('#mermaid-png-' + str(i))
        if el:
            png_bytes = el.screenshot()
            mermaid_images.append("data:image/png;base64," + b64encode(png_bytes).decode())
        else:
            mermaid_images.append(None)

    html = page.content()
    browser.close()

# WeasyPrint doesn't support inline SVG in HTML, which is what MathJax generates,
# so we need to convert the SVG images to base64 strings.
# For some reason, LXML doesn't like closing tags in links immediately following the
# opening tag, so a space must be added for parsing to function correctly.
root = etree.HTML(html.replace("></", "> </"))

mjxs = root.findall('.//mjx-container')
for mjx in mjxs:
    svg = mjx[0]

    # Get the vertical alignment of the SVG element
    svg_style = svg.get("style")

    # The LXML HTML parser puts all the HTML in lower-case, however that makes the SVG
    # invalid, so the "viewbox" element of the svg tag must be replaced with the original "viewBox"
    encoded = b64encode(etree.tostring(svg, method = 'xml', encoding = str).replace("viewbox", "viewBox").encode()).decode()
    data = "data:image/svg+xml;charset=utf8;base64," + encoded
    svg_img = etree.fromstring('<img src="%s"/>' % data)

    # Set the vertical alignment of the new IMG element (style attribute isn't recognized in base64)
    svg_img.set("style", svg_style)

    # Replace the SVG element with the IMG element
    mjx.replace(svg, svg_img)

# Replace each rendered Mermaid container with its screenshot image.
mermaid_blocks = root.xpath('//*[contains(@class, "mermaid")]')
for i, block in enumerate(mermaid_blocks):
    # Only process outermost Mermaid containers; skip any nested inside another.
    parent = block.getparent()
    if parent is not None and 'mermaid' in (parent.get('class') or ''):
        continue
    if i >= len(mermaid_images) or mermaid_images[i] is None:
        continue
    svg_img = etree.fromstring('<img src="%s" class="mermaid-output"/>' % mermaid_images[i])
    block.getparent().replace(block, svg_img)

encoded_html = etree.tostring(root)

vim.command("call s:Progress(3, 'Generating PDF...')")
# Write the final, rendered HTML to a PDF file in the same directory as the Markdown file
HTML(string = encoded_html, base_url = base_url).write_pdf(pdf_path)

# Remove the HTML file that was generated from the Markdown
os.remove(vim.eval("expand('%:p:r')") + ".html")

# Remove the temporary HTML includes file
temp_includes_path = vim.eval("s:temp_includes_path").strip("'")
if os.path.exists(temp_includes_path):
    os.remove(temp_includes_path)
EOF
endfunction

autocmd FileType markdown command! -buffer MarkdownExportPDF call MdToPdf() | redraw! | echom "The PDF was built successfully."
