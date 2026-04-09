" Define plugin default values, if not re-defined by user
if !exists("g:vim_mdtopdf_cssurl")
    let g:vim_mdtopdf_cssurl = "'". shellescape("file://". expand('<sfile>:p:h:h'). "/". "style/md-style.css"). "'"
endif

let s:vim_mdtopdf_html_includes_path = "'". shellescape("file://". expand('<sfile>:p:h:h'). "/". "html-includes/includes.html"). "'"

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

function! MdToPdf()
    " Check that Vim has been compiled with python3 support
    if !has('python3')
        echo "Error: Required vim compiled with +python3"
        finish
    endif

    " Convert the markdown + math to html with pandoc
    lcd %:p:h
    call s:Progress(1, 'Converting Markdown to HTML...')
    let s:pandoc_cmd = "pandoc"
        \ . " -f gfm"
        \ . " --standalone"
        \ . " --css " . g:vim_mdtopdf_cssurl
        \ . " -H " . s:vim_mdtopdf_html_includes_path
        \ . " -o " . shellescape(expand("%:r") . ".html")
        \ . " " . shellescape(expand("%:p"))
    let s:pandoc_out = system(s:pandoc_cmd)
    if v:shell_error
        echoerr "MdToPdf: pandoc failed: " . s:pandoc_out
        finish
    endif

    " Use playwright to render the TeX math using MathJax, then convert the rendered HTML to a PDF
python3 << EOF
import sys
sys.path.insert(0, '/Users/kangtong/.vim/plugged/vim-MdToPdf/.venv/lib/python3.11/site-packages')
from base64 import b64encode
from lxml import etree
import os
import vim
from weasyprint import HTML
from playwright.sync_api import sync_playwright

html_path = "file://" + vim.eval("expand('%:p:r')") + ".html"
pdf_path = vim.eval("expand('%:p:r')") + ".pdf"
base_url = vim.eval("expand('%:p:h')")

vim.command("call s:Progress(2, 'Rendering math...')")
with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page()
    page.goto(html_path)
    page.wait_for_function('mathjax_complete === true')
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
encoded_html = etree.tostring(root)

vim.command("call s:Progress(3, 'Generating PDF...')")
# Write the final, rendered HTML to a PDF file in the same directory as the Markdown file
HTML(string = encoded_html, base_url = base_url).write_pdf(pdf_path)

# Remove the HTML file that was generated from the Markdown
os.remove(vim.eval("expand('%:p:r')") + ".html")
EOF
endfunction

autocmd FileType markdown command! -buffer MarkdownExportPDF call MdToPdf() | redraw! | echom "The PDF was built successfully."
