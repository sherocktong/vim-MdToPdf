# vim-MdToPdf
A Vim plugin utilizing Pandoc, Playwright, and WeasyPrint to convert Markdown documents into PDF files, supporting LaTeX math input via MathJax and Mermaid diagrams.

## Usage
When in a Markdown document, enter normal mode and type `:MarkdownExportPDF` to place a PDF of the Markdown document in the same directory, with the same name.

Running the command the first time may take a few minutes, depending on your internet connection, as a Chromium binary used to render JavaScript may need to be downloaded.

## Installation

### Dependencies
- Python 3
- A version of Vim compiled with Python 3 support (run `vim --version` to check this, if you see `+python3`, you're good)
- The `lxml` Python module
- The `playwright` Python module
- [WeasyPrint](https://weasyprint.org/)
- [Pandoc](https://pandoc.org/)

Clone the repo to the `pack/plugins/start/vim-MdToPdf` directory in your `.vim` folder. If you have another way of installing Vim plugins that you like to use, that'll probably work with this plugin too, however this is untested.

## Configuration
The plugin provides global variables that you can redefine in your `.vimrc` file:
- `g:vim_mdtopdf_cssurl`: Used to define a path or URL for custom CSS (uses the bundled CSS file by default, which is a slight modification of the CSS that Microsoft uses for Markdown in VS Code)
    * You can also use this CSS file to specify your paper size, if you want to use something other than Letter paper
- `g:vim_mdtopdf_mermaid`: Set to `0` to disable Mermaid diagram rendering; default is `1` (enabled)
- `g:vim_mdtopdf_mermaid_url`: URL or local file path for the Mermaid library; default is `https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js`
    * Point this to a local `mermaid.min.js` for offline or air-gapped environments

## Mermaid Diagrams
Mermaid diagrams written in fenced code blocks are rendered in the browser and embedded as images in the exported PDF:

    ```mermaid
    graph TD
        A[Start] --> B{Decision}
        B -->|Yes| C[OK]
        B -->|No| D[Retry]
    ```

Diagram rendering can be disabled with `let g:vim_mdtopdf_mermaid = 0`.
