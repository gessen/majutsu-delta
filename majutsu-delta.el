;;; majutsu-delta.el --- Use Delta when displaying diffs in Majutsu -*- lexical-binding: t; -*-

;; Author: Dan Davison <dandavison7@gmail.com>
;; URL: https://github.com/dandavison/majutsu-delta
;; Version: 0.1
;; Package-Requires: ((emacs "25.1") (xterm-color "2.0"))

;; SPDX-License-Identifier: MIT

;;; Commentary:

;; This package integrates Delta (https://github.com/dandavison/delta) with
;; Majutsu (https://github.com/0WD0/majutsu), so that diffs in Majutsu are
;; displayed with color highlighting provided by Delta.
;;
;; Use M-x majutsu-delta-mode to toggle between using Delta, and normal Majutsu
;; behavior.

;;; Code:
(require 'majutsu)
(require 'xterm-color)
(require 'dash)

(defgroup majutsu-delta nil
  "Majutsu delta customizations."
  :group 'majutsu-diff
  :group 'majutsu-modes)

(defcustom majutsu-delta-delta-executable "delta"
  "The delta executable on your system to be used by Majutsu."
  :type 'string
  :group 'majutsu-delta)

(defcustom majutsu-delta-default-light-theme "GitHub"
  "The default color theme when Emacs has a light background."
  :type 'string
  :group 'majutsu-delta)

(defcustom majutsu-delta-default-dark-theme "Monokai Extended"
  "The default color theme when Emacs has a dark background."
  :type 'string
  :group 'majutsu-delta)

(defcustom majutsu-delta-delta-args
  `("--max-line-distance" "0.6"
    "--true-color" ,(if xterm-color--support-truecolor "always" "never")
    "--color-only")
  "Delta command line arguments as a list of strings.

If the color theme is not specified using --theme, then it will be
chosen automatically according to whether the current Emacs frame has a
light or dark background. See `majutsu-delta-default-light-theme' and
`majutsu-delta-default-dark-theme'.

--color-only is required in order to use delta with majutsu; it
will be added if not present."
  :type '(repeat string)
  :group 'majutsu-delta)

(defcustom majutsu-delta-hide-plus-minus-markers t
  "Whether to hide the +/- markers at the beginning of diff lines."
  :type '(choice (const :tag "Hide" t)
                 (const :tag "Show" nil))
  :group 'majutsu-delta)

(defun majutsu-delta--make-delta-args ()
  "Make final list of delta command-line arguments."
  (let ((args majutsu-delta-delta-args))
    (unless (-intersection '("--syntax-theme" "--light" "--dark") args)
      (setq args (nconc
                  (list "--syntax-theme"
                        (if (eq (frame-parameter nil 'background-mode) 'dark)
                            majutsu-delta-default-dark-theme
                          majutsu-delta-default-light-theme))
                       args)))
    (unless (member "--color-only" args)
      (setq args (cons "--color-only" args)))
    args))

(defvar majutsu-delta--majutsu-diff-refine-hunk--orig-value nil)
(defvar majutsu-delta--majutsu-diff-fontify-hunk--orig-value nil)


;;;###autoload
(define-minor-mode majutsu-delta-mode
  "Use Delta when displaying diffs in Majutsu.

https://github.com/dandavison/delta"
  :lighter " Δ"
  (let ((majutsu-faces-to-override
         '(magit-diff-context-highlight
           magit-diff-added
           magit-diff-added-highlight
           magit-diff-removed
           magit-diff-removed-highlight)))
    (cond
     (majutsu-delta-mode
      (advice-add 'majutsu-diff-wash-diffs :before #'majutsu-delta-call-delta-and-convert-ansi-escape-sequences)
      (setq majutsu-delta--majutsu-diff-refine-hunk--orig-value
            majutsu-diff-refine-hunk

            majutsu-delta--majutsu-diff-fontify-hunk--orig-value
            majutsu-diff-fontify-hunk

            majutsu-diff-refine-hunk
            nil

            majutsu-diff-fontify-hunk
            nil

            face-remapping-alist
            (nconc
             (--remove (member (car it) majutsu-faces-to-override)
                       face-remapping-alist)
             (--map (cons it 'default) majutsu-faces-to-override))))
     ('deactivate
      (advice-remove 'majutsu-diff-wash-diffs #'majutsu-delta-call-delta-and-convert-ansi-escape-sequences)
      (setq majutsu-diff-refine-hunk
            majutsu-delta--majutsu-diff-refine-hunk--orig-value

            majutsu-diff-fontify-hunk
            majutsu-delta--majutsu-diff-fontify-hunk--orig-value

            face-remapping-alist
            (--remove (member (car it) majutsu-faces-to-override)
                      face-remapping-alist))))))

(defun majutsu-delta-call-delta-and-convert-ansi-escape-sequences (_args)
  "Call delta on buffer contents and convert ANSI escape sequences to overlays.

The input buffer contents are expected to be raw git output."
  (apply #'call-process-region
         (point-min) (point-max)
         majutsu-delta-delta-executable t t nil (majutsu-delta--make-delta-args))
  (let ((buffer-read-only nil))
    (xterm-color-colorize-buffer 'use-overlays)
    (if majutsu-delta-hide-plus-minus-markers
        (majutsu-delta-hide-plus-minus-markers))))

(defun majutsu-delta-hide-plus-minus-markers ()
  "Apply text properties to hide the +/- markers at the beginning of lines."
  (save-excursion
    (goto-char (point-min))
    ;; Within hunks, hide - or + at the start of a line.
    (let ((in-hunk nil))
      (while (re-search-forward "^\\(diff\\|@@\\|+\\|-\\)" nil t)
        (cond
         ((string-equal (match-string 0) "diff")
          (setq in-hunk nil))
         ((string-equal (match-string 0) "@@")
          (setq in-hunk t))
         (in-hunk
          (add-text-properties (match-beginning 0) (match-end 0)
                               '(display " "))))))))

(provide 'majutsu-delta)

;;; majutsu-delta.el ends here
