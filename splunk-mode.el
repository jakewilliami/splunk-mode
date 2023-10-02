;;; splunk-mode.el --- Major Mode for editing Splunk Search Processing Language (SPL) source code -*- lexical-binding: t -*-

;; Copyright (C) 2022–2023 Jake Ireland

;; Version: 1.0
;; Author: Jake Ireland <jakewilliami@icloud.com>
;; URL: https://github.com/jakewilliami/splunk-mode/
;; Keywords: languages
;; Package-Requires: ((emacs "23"))

;;; Usage:
;;
;; Put the following code in your .emacs, site-load.el, or other relevant file
;; (add-to-list 'load-path "path-to-splunk-mode")
;; (require 'splunk-mode)

;;; Licence:
;;
;; Permission is hereby granted, free of charge, to any person
;; obtaining a copy of this software and associated documentation
;; files (the "Software"), to deal in the Software without
;; restriction, including without limitation the rights to use, copy,
;; modify, merge, publish, distribute, sublicense, and/or sell copies
;; of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:
;;
;; The above copyright notice and this permission notice shall be
;; included in all copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
;; BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
;; ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
;; CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.

;;; Commentary:
;;
;; Major Mode for editing Splunk Search Processing Language (SPL) source code.
;;
;; Syntax resources:
;;   - https://github.com/splunk/vscode-extension-splunk/
;; 
;; The following resources are from
;; https://docs.splunk.com/Documentation/Splunk/9.1.1/: (or latest)
;;   - SPL: Search/Aboutthesearchlanguage
;;   - SPL Syntax: SearchReference/UnderstandingSPLsyntax
;;
;; Specific resources are referenced where relevant within the code.

;; TODO: Add highlighting of other keywords
;;         - Operators?
;;         - Macro parameters
;;         - Variables
;;         - Comparison or assignment
;;         - Do we need single quotes?
;;         - Embedded block
;; TODO: Handle parentheses outside of escape characters?
;; TODO: Different colour for parentheses (too similar to builtin)
;; TODO: Make keyword highlighting more similar to official splunk
;;       highlighting (i.e., most things are function highlihgts)
;; TODO: Linting/indentation suggestion (similar behaviour to 
;;       julia-mode)
;; TODO: Autocomplete
;; TODO: jump to the opposite side of the blocks with C-M-f and C-M-b
;;       within subsearches
;; ======================================
;; TODO: (defalias 'jai-parent-mode
;;          (if (fboundp 'prog-mode) 'prog-mode 'fundamental-mode))
;; TODO: -beginning-of-defun, -end-of-defun, -indent-line ((setq-local indent-line-function 'simpc-indent-line))
;; TODO: ;; add setq-local for older emacs versions
;;   (unless (fboundp 'setq-local)
;;       (defmacro setq-local (var val)
;;           `(set (make-local-variable ',var) ,val)))
;; TODO: Splunk > splunk
;; TODO: indent on parentheses
;;   NOTE: taken from the scala-indent package and modified for Jai.
;;     Still uses the js-indent-line as a base, which will have to be
;;     replaced when the language is more mature.
;;     (defun jai--indent-on-parentheses ()
;;       (when (and (= (char-syntax (char-before)) ?\))
;;                  (= (save-excursion (back-to-indentation) (point)) (1- (point))))
;;                   (js-indent-line)))
;;     (defun jai--add-self-insert-hooks ()
;;       (add-hook 'post-self-insert-hook
;;         'jai--indent-on-parentheses))
;;     (jai--add-self-insert-hooks)  ;; in mode definition
;; TODO: (font-lock-fontify-buffer)
;; TODO: automatic new line when |?

;;; Code:

;; Need the following to allow GNU Emacs 19 to compile the file.
(eval-when-compile
  (require 'rx)
  (require 'regexp-opt))

(defvar splunk-mode-hook nil)

(defgroup splunk-mode ()
  "Major mode for Splunk SPL code."
  :link '(url-link "https://docs.splunk.com/")
  :version "0.1"
  :group 'languages
  :prefix "splunk-")

;;; Faces

(defface splunk-comment-face
  '((t :inherit font-lock-comment-face))
  "Face for alternative comment syntax in Splunk."
  :group 'splunk-mode)

(defface splunk-builtin-functions-face
  '((t :inherit font-lock-builtin-face))
  "Face for builtin functions such as `rename' and `table' in Splunk."
  :group 'splunk-mode)

(defface splunk-eval-functions-face
  '((t :inherit font-lock-function-name-face))
  "Face for eval functions such as `abs' and `mvindex' in Splunk."
  :group 'splunk-mode)

(defface splunk-transforming-functions-face
  '((t :inherit font-lock-function-name-face))
  "Face for transforming functions such as `count' and `values' in Splunk."
  :group 'splunk-mode)

(defface splunk-constants-face
  '((t :inherit font-lock-preprocessor-face))
  "Face for language constants such as `as' and `by' in Splunk."
  :group 'splunk-mode)

(defface splunk-macros-face
  '((t :inherit font-lock-function-name-face))
  "Face for macros in Splunk."
  :group 'splunk-mode)

(defface splunk-digits-face
  ;; '((t :inherit font-lock-number-face))  ;; Added too recently
  '((t :inherit font-lock-type-face))
  "Face for digits in Splunk."
  :group 'splunk-mode)

(defface splunk-escape-chars-face
  ;; '((t :inherit font-lock-escape-face))  ;; Added too recently
  '((t :inherit font-lock-constant-face))
  "Face for escape characters in Splunk."
  :group 'splunk-mode)

(defface splunk-operators-face
  '((t :inherit font-lock-builtin-face
       :weight bold))
  "Face for operators in Splunk."
  :group 'splunk-mode)

(defface splunk-keyword-face
  '((t :inherit font-lock-function-call-face
       :weight bold))
  "Face for keywords (e.g. `sourcetype=*') in Splunk."
  :group 'splunk-mode)

;;; Syntax

(defconst splunk-mode-syntax-table
  (with-syntax-table (copy-syntax-table)
    ;; C/C++ style comments
	(modify-syntax-entry ?/ ". 124b")
	(modify-syntax-entry ?* ". 23")
	(modify-syntax-entry ?\n "> b")

    ;; Chars are the same as strings
    (modify-syntax-entry ?' "\"")
    (syntax-table))
  "Syntax table for `splunk-mode'.")

(eval-and-compile
  (defconst splunk-builtin-functions
    '("abstract" "accum" "addcoltotals" "addinfo" "addtotals"
      "analyzefields" "anomalies" "anomalousvalue" "append"
      "appendcols" "appendpipe" "arules" "associate" "audit"
      "autoregress" "bucket" "bucketdir" "chart" "cluster"
      "collect" "concurrency" "contingency" "convert" "correlate"
      "crawl" "datamodel" "dbinspect" "dbxquery" "dbxlookup"
      "dedup" "delete" "delta" "diff" "dispatch" "erex" "eval"
      "eventcount" "eventstats" "extract" "fieldformat" "fields"
      "fieldsummary" "file" "filldown" "fillnull" "findtypes"
      "folderize" "foreach" "format" "from" "gauge" "gentimes"
      "geostats" "head" "highlight" "history" "input" "index"
      "inputcsv" "inputlookup" "iplocation" "join" "kmeans" "kvform"
      "loadjob" "localize" "localop" "lookup" "makecontinuous"
      "makemv" "makeresults" "map" "metadata" "metasearch"
      "multikv" "multisearch" "mvcombine" "mvexpand" "nomv"
      "outlier" "outputcsv" "outputlookup" "outputtext" "overlap"
      "pivot" "predict" "rangemap" "rare" "regex" "relevancy"
      "reltime" "rename" "replace" "rest" "return" "reverse"
      "rex" "rtorder" "run" "savedsearch" "script" "scrub"
      "search" "searchtxn" "selfjoin" "sendemail" "set" "setfields"
      "sichart" "sirare" "sistats" "sitimechart" "sitop" "sort"
      "spath" "stats" "strcat" "streamstats" "table" "tags"
      "tail" "timechart" "top" "transaction" "transpose" "trendline"
      "tscollect" "tstats" "typeahead" "typelearner" "typer" "uniq"
      "untable" "where" "x11" "xmlkv" "xmlunescape" "xpath"
      "xyseries"))

  (defconst splunk-eval-functions
     '("abs" "acos" "acosh" "asin" "asinh" "atan" "atan2" "atanh"
       "case" "cidrmatch" "ceiling" "coalesce" "commands" "cos"
       "cosh" "exact" "exp" "floor" "hypot" "if" "in" "isbool"
       "isint" "isnotnull" "isnull" "isnum" "isstr" "len" "like"
       "ln" "log" "lower" "ltrim" "match" "max" "md5" "min" "mvappend"
       "mvcount" "mvdedup" "mvfilter" "mvfind" "mvindex" "mvjoin"
       "mvrange" "mvsort" "mvzip" "now" "null" "nullif" "pi" "pow"
       "printf" "random" "relative_time" "replace" "round" "rtrim"
       "searchmatch" "sha1" "sha256" "sha512" "sigfig" "sin" "sinh"
       "spath" "split" "sqrt" "strftime" "strptime" "substr" "tan"
       "tanh" "time" "tonumber" "tostring" "trim" "typeof" "upper"
       "urldecode" "validate"))

  (defconst splunk-transforming-functions
     '("avg" "count" "distinct_count" "estdc" "estdc_error" "eval"
       "max" "mean" "median" "min" "mode" "percentile" "range"
       "stdev" "stdevp" "sum" "sumsq" "var" "varp" "first" "last"
       "list" "values" "earliest" "earliest_time" "latest"
       "latest_time" "per_day" "per_hour" "per_minute" "per_second"
       "rate"))

  ;; TODO: improve "case-insensitive" workaround
  (defconst splunk-language-constants-lower
     '("as" "by" "or" "and" "over" "where" "output" "outputnew" "not"
       "true" "false"))
  (defconst splunk-language-constants
     (append splunk-language-constants-lower (mapcar 'upcase splunk-language-constants-lower))))

;; A Splunk word can contain underscores.  To use in the place of `word'
;;
;; Reference on extending rx:
;;   - https://www.gnu.org/software/emacs/manual/html_node/elisp/Extending-Rx.html
;;   - https://emacs.stackexchange.com/q/79050
(rx-define splunk-word
   (or word "_"))

;; "(?<=\\`)[\\w]+(?=\\(|\\`)"
(defconst splunk-macro-names-regexp
   (rx "`" (group (one-or-more splunk-word)) (or "(" "`")))

;; "\\b(\\d+)\\b"
(defconst splunk-digits-regexp
   (rx word-boundary (group (one-or-more digit)) word-boundary))

;; "(\\\\\\\\|\\\\\\||\\\\\\*|\\\\\\=)"
(defconst splunk-escape-chars-regexp
   (rx (group (or "\\\\" "\\*" "\\|" "\\=" "(" ")" "[" "]"))))

;; "(\\|,)"
(defconst splunk-operators-regexp
   ;; (rx (group (or "\\" ","))))
   (rx unmatchable))

;; E.g., sourcetype=access_*
(defconst splunk-keyword-regexp
   (rx (and (group (one-or-more splunk-word))
            (optional (one-or-more space))  "=" (optional (one-or-more space))
            (or (one-or-more digit)
                (and (optional "\"") (one-or-more (or "*" splunk-word)) (optional "\""))))))

;; Alternative comment syntax; ref:
;;   - https://docs.splunk.com/Documentation/Splunk/9.1.1/Search/Comments
;;   - https://docs.splunk.com/Documentation/SCS/current/Search/Comments
;;   - https://docs.splunk.com/Documentation/Splunk/8.0.10/Search/Addcommentstosearches
(defconst splunk-special-comment-regexp
   (rx (or
           ;; Triple backtick style
           (and (repeat 3 "`") (zero-or-more anything) (repeat 3 "`"))
           ;; Comment macro
           (and "`comment(\"" (zero-or-more anything) "\")`"))));;
  ;; )

;; Relevant refs
;;   - Font faces: https://www.gnu.org/software/emacs/manual/html_node/elisp/Faces-for-Font-Lock.html
;;   - Regex: https://www.gnu.org/software/emacs/manual/html_node/elisp/Rx-Constructs.html
;;
;; Note the double apostrophe before providing custom type faces:
;;   - https://emacs.stackexchange.com/a/3587
(defconst splunk-font-lock-keywords
  (list
   ;; Syntax defined by keyword lists
   (cons (regexp-opt splunk-builtin-functions 'symbols) ''splunk-builtin-functions-face)
   (cons (regexp-opt splunk-eval-functions 'symbols) ''splunk-eval-functions-face)
   (cons (regexp-opt splunk-transforming-functions 'symbols) ''splunk-transforming-functions-face)
   (cons (regexp-opt splunk-language-constants 'symbols) ''splunk-language-constants-face)

   ;; Alternative comment styles
   ;;
   ;; Note the syntax-level override:
   ;;   - https://emacs.stackexchange.com/a/79049
   ;;   - https://stackoverflow.com/a/24107675
   ;;   - https://emacs.stackexchange.com/a/61891
   (list splunk-special-comment-regexp 0 ''splunk-comment-face t)

   ;; Syntax defined by regex
   ;;
   ;; Note the extraction of specific groups from the regex:
   ;;   - https://emacs.stackexchange.com/a/79044
   (list splunk-macro-names-regexp 1 ''splunk-macros-face)
   (cons splunk-digits-regexp ''splunk-digits-face)
   (cons splunk-escape-chars-regexp ''splunk-escape-chars-face)
   (cons splunk-operators-regexp ''splunk-operators-face)
   (list splunk-keyword-regexp 1 ''splunk-keyword-face)))

;;; Mode

;;;###autoload
(define-derived-mode splunk-mode prog-mode "splunk"
  "Major Mode for editing Splunk SPL source code."
  :syntax-table splunk-mode-syntax-table
  (setq-local font-lock-defaults '(splunk-font-lock-keywords))
  (setq-local comment-start "//"))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.spl\\'" . splunk-mode))
(add-to-list 'auto-mode-alist '("\\.splunk\\'" . splunk-mode))

(provide 'splunk-mode)

;;; splunk-mode.el ends here
