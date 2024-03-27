;;; splunk-mode.el --- Major Mode for editing Splunk Search Processing Language (SPL) source code -*- lexical-binding: t -*-

;; Copyright (C) 2022–2024 Jake Ireland

;; Author: Jake Ireland <jakewilliami@icloud.com>
;; URL: https://github.com/jakewilliami/splunk-mode/
;; Version: 1.0
;; Keywords: languages splunk mode
;; Package-Requires: ((emacs "27"))

;;; Usage:
;;
;; Put the following code in your .emacs, site-load.el, or other relevant file
;; (add-to-list 'load-path "path-to-splunk-mode")
;; (require 'splunk-mode)

;;; Licence:
;;
;; This file is not part of GNU Emacs.
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
;; This package provides syntax highlighting and indentation support for
;; SPL source code.
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

;;; Notes:
;;
;; TODO:
;;   - only highlight transforming and eval functions after parentheses added
;;   - I need to go through and actually test things at some point, but I should probably prioritise releasing this and doing small touch-ups later
;;   - Electric indent mode (see below)
;;
;; NOTE: Feature possibilities:
;;   - Operator highlighting
;;   - Comparison or assignment highlighting
;;   - Different brackets colours when nested
;;   - Make keyword highlighting more similar to official Splunk
;;     highlighting (i.e., most things are function highlights.)
;;   - Linting
;;   - Autocomplete

;;; Code



;;; Main

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
;;
;; Custom font faces for Splunk syntax.
;;
;; After some trial and error, and taking inspiration from different places, here are
;; some possible colour schemes:*
;;
;;  ----------------------------------------------------------------------------
;; | font-lock-*-face  | Apt              | Falcon           | VS Code          |
;; |-------------------|------------------|------------------|------------------|
;; | warning           | —                | —                | —                |
;; | function-name     | Trans/Eval/Macro | Builtin          | Constants        |
;; | [n] function-call | —                | —                | —                |
;; | variable-name     | Keyword          | —                | Keyword          |
;; | [n] variable-use  | —                | —                | —                |
;; | keyword           | —                | Trans/Eval/Macro | —                |
;; | type              | —                | Constants        | Trans/Eval/Macro |
;; | constant          | Constants        | Keyword          | Builtin          |
;; | builtin           | Builtin          | —                | —                |
;; | preprocessor      | —                | —                | —                |
;; | [n] property-name | —                | —                | —                |
;; | [n] number        | —                | —                | —                |
;; | [n] escape        | —                | —                | —                |
;;  ----------------------------------------------------------------------------
;;
;; Note: font-lock faces prefixed with [n] have been considered too new to use here,
;; as they do not yet have enough widespread support.
;;
;; Ref:
;;   - https://www.gnu.org/software/emacs/manual/html_node/elisp/Faces-for-Font-Lock.html

(defface splunk-comment-face
  '((t :inherit font-lock-comment-face))
  "Face for alternative comment syntax in Splunk."
  :group 'splunk-mode)

(defface splunk-builtin-functions-face
  '((t :inherit font-lock-builtin-face))
  ;; '((t :inherit font-lock-function-name-face))
  ;; '((t :inherit font-lock-constant-face))
  "Face for builtin functions such as `rename', `table', and `stat' in Splunk."
  :group 'splunk-mode)

(defface splunk-eval-functions-face
  '((t :inherit font-lock-function-name-face))
  ;; '((t :inherit font-lock-keyword-face))
  ;; '((t :inherit font-lock-type-face))
  "Face for eval functions such as `abs' and `mvindex' in Splunk."
  :group 'splunk-mode)

(defface splunk-transforming-functions-face
  '((t :inherit font-lock-function-name-face))
  ;; '((t :inherit font-lock-keyword-face))
  ;; '((t :inherit font-lock-type-face))
  "Face for transforming functions such as `count' and `values' in Splunk."
  :group 'splunk-mode)

(defface splunk-language-constants-face
  '((t :inherit font-lock-constant-face))
  ;; '((t :inherit font-lock-type-face))
  ;; '((t :inherit font-lock-function-name-face))
  "Face for language constants such as `as' and `by' in Splunk."
  :group 'splunk-mode)

(defface splunk-macros-face
  '((t :inherit font-lock-function-name-face))
  ;; '((t :inherit font-lock-keyword-face))
  ;; '((t :inherit font-lock-type-face))
  "Face for macros in Splunk."
  :group 'splunk-mode)

(defface splunk-keyword-face
  '((t :inherit font-lock-variable-name-face))
  ;; '((t :inherit font-lock-constant-face))
  ;; '((t :inherit font-lock-variable-name-face))
  "Face for keywords (e.g. `sourcetype=*') in Splunk."
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



;;; Syntax

;; Update syntax table; refs:
;;   - https://www.gnu.org/software/emacs/manual/html_node/elisp/Syntax-Table-Functions.html
;;   - https://www.gnu.org/software/emacs/manual/html_node/elisp/Syntax-Flags.html
;;   - https://www.gnu.org/software/emacs/manual/html_node/elisp/Syntax-Descriptors.html
;;   - https://www.gnu.org/software/emacs/manual/html_node/elisp/Syntax-Class-Table.html
(defconst splunk-mode-syntax-table
  (with-syntax-table (copy-syntax-table)
    ;; C/C++ style comments
	(modify-syntax-entry ?/ ". 124b")
	(modify-syntax-entry ?* ". 23")
	(modify-syntax-entry ?\n "> b")

    ;; The pipe character needs to be counted as a symbol-constituent
    ;; character, so that symbols are broken up by pipes; refs:
    (modify-syntax-entry ?| " ")

    ;; Chars are the same as strings
    (modify-syntax-entry ?' "\"")

    ;; Syntax table
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
;;   - https://emacsdocs.org/docs/elisp/Rx-Notation#macro-rx-define-name-arglist-rx-form
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

;; E.g., `sourcetype=access_*'
(defconst splunk-keyword-regexp
   (rx (and (group (one-or-more splunk-word))
            (optional (one-or-more space))  "=" (optional (one-or-more space))
            (or (one-or-more digit)
                (and (optional "\"") (one-or-more (or "*" splunk-word)) (optional "\""))))))

;; Only highlight eval functions in eval blocks
;; E.g., `eval isLocalAdmin=if(...)'; ref:
;;   - https://docs.splunk.com/Documentation/Splunk/9.2.0/SearchReference/CommonEvalFunctions
(defconst splunk-eval-regexp
  (rx (and
       (group (and
               (or "eval" "where" "fieldformat")
               (or (one-or-more space) eol)
               (zero-or-more (not (any "|[")))))
       (group (regexp (regexp-opt splunk-eval-functions 'words))))))

;; Alternative comment syntax; refs:
;;   - https://docs.splunk.com/Documentation/Splunk/9.1.1/Search/Comments
;;   - https://docs.splunk.com/Documentation/SCS/current/Search/Comments
;;   - https://docs.splunk.com/Documentation/Splunk/8.0.10/Search/Addcommentstosearches
(defconst splunk-alt-comment-regexp
   (rx (or
        ;; Triple backtick style
        (and (repeat 3 "`") (zero-or-more not-newline) (repeat 3 "`"))
        ;; Comment macro
        (and "`comment(\"" (zero-or-more not-newline) "\")`"))))

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
   (cons (regexp-opt splunk-transforming-functions 'symbols) ''splunk-transforming-functions-face)
   (cons (regexp-opt splunk-language-constants 'symbols) ''splunk-language-constants-face)

   ;; Eval functions
   ;; (cons splunk-eval-regexp ''splunk-eval-functions-face)
   (list splunk-eval-regexp 2 ''splunk-eval-functions-face)

   ;; Alternative comment styles
   ;;
   ;; Note the syntax-level override:
   ;;   - https://emacs.stackexchange.com/a/79049
   ;;   - https://stackoverflow.com/a/24107675
   ;;   - https://emacs.stackexchange.com/a/61891
   (list splunk-alt-comment-regexp 0 ''splunk-comment-face t)

   ;; Syntax defined by regex
   ;;
   ;; Note the extraction of specific groups from the regex:
   ;;   - https://emacs.stackexchange.com/a/79044
   (list splunk-macro-names-regexp 1 ''splunk-macros-face)
   (cons splunk-digits-regexp ''splunk-digits-face)
   (cons splunk-escape-chars-regexp ''splunk-escape-chars-face)
   (cons splunk-operators-regexp ''splunk-operators-face)
   (list splunk-keyword-regexp 1 ''splunk-keyword-face)))



;;; Indentation and Electricity

;; Handle indentation for SPL code.
;;
;; Inspired by similar functions from groovy-mode.el:
;;   - https://github.com/Groovy-Emacs-Modes/groovy-emacs-modes/blob/7b8520b2/groovy-mode.el#L751-L770
;;   - https://github.com/Groovy-Emacs-Modes/groovy-emacs-modes/blob/7b8520b2/groovy-mode.el#L837-L986
;;
;; Refs:
;;   - https://www.gnu.org/software/emacs/manual/html_node/elisp/Position-Parse.html
;;   - https://www.gnu.org/software/emacs/manual/html_node/elisp/Parser-State.html
;;   - https://www.gnu.org/software/emacs/manual/html_node/eintr/nth.html

(defcustom splunk-indent-offset 4
  "Indentation amount for Splunk."
  :type 'natnum
  :safe #'natnum
  :group 'splunk-mode)

;; Always indent with spaces
(setq-local indent-tabs-mode nil)


;; NOTE: I don't know how this function works.  I had to reverse the logic for it
;;  to work as expected, but I would have thought it should work without the `not'
(defun splunk--is-square-bracket-p (pos)
  "Check if the parenthesis at `pos' is a square bracket."
  (let ((parse-state (parse-partial-sexp (point-min) pos)))
    (not (= (char-after (nth 8 parse-state)) ?\[))))

(defun splunk--effective-depth (pos)
  "Get effective depth at `pos' in SPL query."
  (let ((paren-depth 0)
        (syntax (syntax-ppss pos))
        (current-line (line-number-at-pos pos)))
    (save-excursion
      ;; Keep going whilst we're inside parentheses
      (while (> (nth 0 syntax) 0)
        ;; Go to the most recent enclosing open parenthesis
        (goto-char (nth 1 syntax))

        ;; Count this paren, but only if it was on another line
	    ;; TODO: doc: or if it was open square
        (let ((new-line (line-number-at-pos (point))))
          (unless (or (= new-line current-line)
                      (splunk--is-square-bracket-p (point)))
            (setq paren-depth (1+ paren-depth))
            (setq current-line new-line)))

        (setq syntax (syntax-ppss (point)))))
    paren-depth))

(defun splunk--current-line ()
  "The current line enclosing point."
  (buffer-substring-no-properties
   (line-beginning-position) (line-end-position)))

(defun splunk-indent-line ()
  "Indent the current line according to the number of parentheses."
  (interactive)
  ;; TODO: consider indenting line if it is not the first line in the search.
  ;;  However, this is a personal stylistic preference rather than standard
  (let* ((current-depth (splunk--effective-depth (line-beginning-position)))
         (current-line (s-trim (splunk--current-line)))
  )

  ;; If this line starts with a closing paren, unindent by one level
  (when (s-starts-with-p "]" current-line)
    (setq current-depth (1- current-depth)))

  ;; `current-depth' should never be negative, unless the source
  ;; has unbalanced brackets.  Ensure we handle this robustly
  (when (< current-depth 0)
    (setq current-depth 0))

  ;; Indent region!
  (let ((indent-level current-depth))
    (indent-line-to (* splunk-indent-offset indent-level)))
))

;; Handle automatic new lines TODO OOOO)))OOOOOOOOOOOOO doc


;; https://www.emacswiki.org/emacs/Electricity

(defvar electric-pair-inhibit-predicate)
(defvar electric-pair-skip-self) ;; TODO
(defvar electric-indent-chars)

;; (defun splunk--insert-newline-after-open-bracket ()
  ;; ""
  ;; (interactive)
  ;; (insert "[")
  ;; (if (eq (char-before) ?\[)
      ;; (progn (newline) (indent-according-to-mode))))



(defun splunk--insert-pipe ()
  "Insert a new line and auto-indent after a `|' character."
  (interactive)
  (insert "|")
  (newline))

(defun splunk--insert-open-bracket ()
  "Insert a new line and auto-indent after a `\[' character."
  (interactive)
  (insert "[")
  (newline-and-indent))

;; (defun splunk--electric-indent ()
  ;; "Custom Electric Indent rules for Splunk mode."
  ;; (setq-local electric-indent-chars (append electric-indent-chars '(?| ?\[))))

;; (defun splunk--electric-indent ()
  ;; "Custom electric indent function for Splunk mode."
  ;; (interactive)
  ;; (let ((char (char-before)))
    ;; (if (or (eq char ?|) (eq char ?[))
        ;; (progn
          ;; (newline)
          ;; (indent-according-to-mode))
      ;; (self-insert-command 1))))

;; (add-hook 'splunk-mode-hook 'electric-indent-mode-hook)
;; (add-hook 'splunk-mode-hook 'splunk--electric-indent)

;; (defvar splunk-mode-map
  ;; (let ((m (make-sparse-keymap)))
    ;; (unless (boundp 'electric-indent-chars)
      ;; (define-key m "[" #'splunk--insert-open-bracket)
      ;; (define-key m "|" #'splunk--insert-pipe))
    ;; m)
  ;; "Keymap used by ‘splunk-mode’.")

(defun splunk--indent-post-self-insert-function ()
  ""
  (when (and electric-indent-mode
             (eq (char-before) last-command-event))
    (cond
     ;; Electric indent inside parens
     
    )
  ))



;; (defconst splunk-electric-layout-rules
  ;; (list
    ;; (cons ?\[ . before)
  ;; ))




;;; Mode

;;;###autoload
(define-derived-mode splunk-mode prog-mode "Splunk"
  "Major Mode for editing Splunk SPL source code.

\\{splunk-mode-map}"
  :syntax-table splunk-mode-syntax-table
  (setq-local font-lock-defaults '(splunk-font-lock-keywords))
  ;; (setq-local comment-start "//")
  (setq-local indent-line-function 'splunk-indent-line)
  ;; (electric-indent-local-mode 1)
    ;; (electric-indent-mode 1)
  ;; set electric characters
  ;; (setq-local electric-indent-chars
  ;; (append "|[]" electric-indent-chars))
  ;; (setq-local electric-indent-chars (append electric-indent-chars '(?| ?\[))) ;; THIS ONE
  ;; Auto indent on |
  ;; (setq-local electric-indent-chars
              ;; (cons ?| (and (boundp 'electric-indent-chars)
                            ;; electric-indent-chars)))


  
  ;; (add-hook 'post-self-insert-hook
            ;; #'splunk--indent-post-self-insert-function 'append 'local)

  ;; (when (boundp 'electric-indent-chars)
    ;; (set (make-local-variable 'electric-indent-chars) '(?| ?\[))
    ;; (add-hook 'electric-indent-functions #'splunk--electric-indent-function nil t)
  ;; )
  
  ;; (electric-indent-mode 1)
  ;; Closing square bracket should re-indent (i.e. unindent) the line
  ;; FOR electric-indent-mode THIS ONE
  ;; (when (boundp 'electric-indent-chars)
    ;; (setq-local electric-indent-chars
                ;; (append electric-indent-chars '(?|))))

  ;; FOR electric-layout-mode
  ;; (setq-local electric-layout-rules splunk-electric-layout-rules)
  ;; requires electric-layout-mode
  (setq electric-layout-rules '((?\[ . before) (?| . before)))
  ;; (add-to-list 'electric-layout-rules
               ;; '((?\[ . before)
                 ;; (?| . before)))

  (add-to-list 'electric-layout-rules '(?| . before))
  ;; requires electric-indent-mode
  (setq-local electric-indent-chars
              (cons ?\] (and (boundp 'electric-indent-chars)
                             electric-indent-chars)))

  (font-lock-fontify-buffer))

;; (add-hook 'lisp-mode-hook #'(lambda ()
;; (local-set-key (kbd "RET") 'newline-and-indent)))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.spl\\'" . splunk-mode))
(add-to-list 'auto-mode-alist '("\\.splunk\\'" . splunk-mode))

(provide 'splunk-mode)



;; Local Variables:
;; coding: utf-8
;; checkdoc-major-mode: t
;; End:

;;; splunk-mode.el ends here




;; (setq electric-layout-rules )






;; electric-indent-just-newline
;; electric-layout-rules
;; electric-pair-mode
