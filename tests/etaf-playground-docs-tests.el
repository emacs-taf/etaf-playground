;;; etaf-playground-docs-tests.el --- Documentation contracts -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)

(defconst etaf-playground-docs-tests--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Absolute etaf-playground repository root.")

(defun etaf-playground-docs-tests--contents (name)
  "Return the literal contents of repository file NAME."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name name etaf-playground-docs-tests--root))
    (buffer-string)))

(defun etaf-playground-docs-tests--normalized-contents (name)
  "Return NAME with runs of whitespace collapsed for prose assertions."
  (replace-regexp-in-string
   "[[:space:]]+" " " (etaf-playground-docs-tests--contents name)))

(ert-deftest etaf-performance-docs-distinguish-evidence-lanes ()
  "Latency, trace, and GUI evidence remain explicitly separate lanes."
  (dolist (file '("README.md" "DESIGN.md" "DESIGN.zh-CN.md"))
    (let ((text (etaf-playground-docs-tests--normalized-contents file)))
      (should (string-match-p "latency lane\\|延迟 lane" text))
      (should (string-match-p "trace lane\\|追踪 lane" text))
      (should (string-match-p "GUI lane" text))
      (should (string-match-p
               "repository/environment/scenario/fixture/build identity\\|仓库、环境、场景、fixture 和 build identity"
               text))
      (should (string-match-p
               "not GUI first paint\\|不是 GUI first paint"
               text)))))

(ert-deftest etaf-performance-docs-separate-current-gate-from-historical-budget ()
  "The active 50ms gate must not be confused with the historical 105ms text."
  (dolist (file '("DESIGN.md" "DESIGN.zh-CN.md"))
    (let ((text (etaf-playground-docs-tests--normalized-contents file)))
      (should (string-match-p "5.*warmup.*30.*sample\\|5.*warmup.*30.*sample" text))
      (should (string-match-p "p95.*max.*50ms\\|p95.*max.*50ms" text))
      (should (string-match-p "105ms p50" text))
      (should (string-match-p "historical\\|历史" text))
      (should (string-match-p "M0b1" text)))))

(provide 'etaf-playground-docs-tests)
;;; etaf-playground-docs-tests.el ends here
