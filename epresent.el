;;; epresent.el --- Simple presentation mode for Emacs Org-mode

;; Copyright (C) 2008 Tom Tromey <tromey@redhat.com>
;;               2010 Eric Schulte <schulte.eric@gmail.com>

;; Authors: Tom Tromey <tromey@redhat.com>, Eric Schulte <schulte.eric@gmail.com>, Lee Hinman <lee@writequit.org>
;; URL: https://github.com/dakrone/epresent
;; Created: 12 Jun 2008
;; Version: 1.0.0
;; Keywords: gui
;; Package-Requires: ((org "8") (cl-lib "0.5"))

;; This file is not (yet) part of GNU Emacs.
;; However, it is distributed under the same license.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; This is a simple presentation mode for Emacs. It works best in
;; Emacs >= 24, which has a nice font rendering engine.

;; To use, invoke `epresent-run' in an `org-mode' buffer. This will
;; make a full-screen frame. Use n/p to navigate, or q to quit. Read
;; below for more key bindings. Each top-level headline becomes a
;; frame in the presentation (configure `EPRESENT_FRAME_LEVEL' to
;; change this default). Org-mode markup is used to nicely display the
;; buffer's contents.

;;; Code:
(require 'org)
(require 'ox)
(require 'ox-latex)
(require 'cl-lib)
(require 'org-superstar)

(defgroup epresent nil
  "This is a simple presentation mode for Emacs."
  :group 'epresent)

(defface epresent-title-face
  '((t :weight bold :height 360 :underline t :inherit variable-pitch))
  "Face used for the title of the document during the presentation."
  :group 'epresent)
(defface epresent-heading-face
  '((t :weight bold :height 270 :underline t :inherit variable-pitch))
  "Face used for the top-level headings in the outline during the presentation."
  :group 'epresent)
(defface epresent-subheading-face
  '((t :weight bold :height 240 :inherit variable-pitch))
  "Face used for any non-top-level headings in the outline during the presentation."
  :group 'epresent)
(defface epresent-author-face
  '((t :height 1.6 :inherit variable-pitch))
  "Face used for the author of the document during the presentation."
  :group 'epresent)
(defface epresent-bullet-face
  '((t :weight bold :height 1.4 :underline nil :inherit variable-pitch))
  "Face used for bullets during the presentation."
  :group 'epresent)
(defface epresent-hidden-face
  '((t :invisible t))
  "Face used for hidden elements during the presentation."
  :group 'epresent)

(defvar epresent--frame nil
  "Frame for EPresent.")

(defvar epresent--org-buffer nil
  "Original Org-mode buffer")

(defvar epresent--org-restriction nil
  "Original restriction in Org-mode buffer.")

(defvar epresent--org-file nil
  "Temporary Org-mode file used when a narrowed region.")

(defvar epresent-overlays nil)
(defvar epresent-fringe-overlays nil)
(defvar epresent-inline-image-overlays nil)
(defvar epresent-src-fontify-natively nil)
(defvar epresent-hide-emphasis-markers nil)
(defvar epresent-outline-ellipsis nil)
(defvar epresent-pretty-entities nil)
(defvar epresent-page-number 0)

(defcustom epresent-indicators t
  "If not nil, display a dot in the top right corner if the
current page has an EPRESENT_SHOW_FILE property, and display two
dots if it has an EPRESENT_SHOW_VIDEO property."
  :type 'boolean
  :group 'epresent)

(defcustom epresent-slide-in nil
  "Apply slide-in effect when changing slides. If set globally,
slide-in can be inhibited for a specific heading by setting the
EPRESENT_SLIDE_IN property to 'no'."
  :type 'boolean
  :group 'epresent)

(defcustom epresent-slide-in-lines 10
  "When slide in is used, how many lines from below the header
are used for the slide-in animation."
  :type 'number
  :group 'epresent)

(defcustom epresent-slide-in-duration 0.250
  "When slide-in is used, duration of the effect, in seconds."
  :type 'number
  :group 'epresent)

(defcustom epresent-slide-in-pause 1
  "Pause after changing slide, before the slide-in kicks in."
  :type 'number
  :group 'epresent)

(defcustom epresent-text-scale 400
  "Height for the text size when presenting."
  :type 'number
  :group 'epresent)

(defcustom epresent-format-latex-scale 4
  "A scaling factor for the size of the images generated from LaTeX."
  :type 'number
  :group 'epresent)

(defcustom epresent-internal-border-width 75
  "The internal border will be the number of pixels of margin
between your text and the screen borders. Increase (decrease) to
leave more (less)."
  :type 'integer
  :group 'epresent)

(defcustom epresent-hide-todos t
  "Whether or not to hide TODOs during the presentation."
  :type 'boolean
  :group 'epresent)

(defcustom epresent-hide-tags t
  "Whether or not to hide tags during the presentation."
  :type 'boolean
  :group 'epresent)

(defcustom epresent-hide-properties t
  "Whether or not to hide properties during the presentation."
  :type 'boolean
  :group 'epresent)

(defcustom epresent-mode-line '(:eval (int-to-string epresent-page-number))
  "Set the mode-line format. Hides it when nil"
  :type 'string
  :group 'epresent)

(defcustom epresent-src-blocks-visible t
  "If non-nil source blocks are initially visible on slide change.
If nil then source blocks are initially hidden on slide change."
  :type 'boolean
  :group 'epresent)

(defcustom epresent-start-presentation-hook nil
  "Hook run after starting a presentation."
  :type 'hook
  :group 'epresent)
(defcustom epresent-stop-presentation-hook nil
  "Hook run before stopping a presentation."
  :type 'hook
  :group 'epresent)

(defvar epresent-frame-level 1)

(defvar epresent-src-block-toggle-state nil)

(defvar epresent-show-filename nil)

(defvar epresent-auxiliary-window nil)

(defvar epresent-show-buffer nil)

(defun epresent--get-frame ()
  (unless (frame-live-p epresent--frame)
    (setq epresent--frame (make-frame '((minibuffer . nil)
                                        (title . "EPresent")
                                        (fullscreen . fullboth)
                                        (menu-bar-lines . 0)
                                        (tool-bar-lines . 0)
                                        (vertical-scroll-bars . nil)
                                        (left-fringe . 0)
                                        (right-fringe . 10)
                                        (internal-border-width . 50)
					(right-divider-width . 0)
                                        (cursor-type . nil)
                                        ))))
  (raise-frame epresent--frame)
  (select-frame-set-input-focus epresent--frame)
  (set-face-background 'fringe "white")
  epresent--frame)

;; functions
(defun epresent-get-frame-level ()
  "Get the heading level to show as different frames."
  (interactive)
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (if (re-search-forward
           "^#\\+EPRESENT_FRAME_LEVEL:[ \t]*\\(.*?\\)[ \t]*$" nil t)
          (string-to-number (match-string 1))
        1))))

(defun epresent-get-mode-line ()
  "Get the presentation-specific mode-line."
  (interactive)
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (if (re-search-forward
           "^#\\+EPRESENT_MODE_LINE:[ \t]*\\(.*?\\)[ \t]*$" nil t)
          (car (read-from-string (match-string 1)))
        epresent-mode-line))))

(defun epresent-goto-top-level ()
  "Go to the current top level heading containing point."
  (interactive)
  (unless (org-at-heading-p) (outline-previous-heading))
  (let ((level (ignore-errors (org-reduced-level (org-current-level)))))
    (when (and level (> level epresent-frame-level))
      (org-up-heading-all (- level epresent-frame-level)))))

(defun epresent-jump-to-page (num)
  "Jump directly to a particular page in the presentation."
  (interactive "npage number: ")
  (epresent-top)
  (dotimes (_ (1- num)) (epresent-next-page)))

(defun epresent-current-page ()
  "Present the current outline heading."
  (interactive)
  (when epresent-auxiliary-window
    (message "deleting aux window")
    (delete-window epresent-auxiliary-window)
    (setq epresent-auxiliary-window nil))
  (if (org-current-level)
      (progn
        (epresent-goto-top-level)
        (org-narrow-to-subtree)
        (outline-show-all)
        (outline-hide-body)
        (when (>= (org-reduced-level (org-current-level))
                  epresent-frame-level)
	  (org-show-subtree)
	  (org-set-visibility-according-to-property) ;; folds children
          (let ((epresent-src-block-toggle-state
                 (if epresent-src-blocks-visible :show :hide)))
            (epresent-toggle-hide-src-blocks))))
    ;; before first headline -- fold up subtrees as TOC
    (org-cycle '(4))))

(defun epresent-show-indicators ()
  ""
  (interactive)
  (setq show-file nil)
  (save-excursion
    (goto-char (point-min))
    (end-of-line)
    (when (org-entry-get nil "EPRESENT_SHOW_FILE")
      (setq show-file t)
      (add-to-list 'epresent-fringe-overlays (make-overlay (point) (point)))
      (overlay-put (car epresent-fringe-overlays)
		   'before-string
		   (propertize " " 'display '(right-fringe filled-square))))
    (when (org-entry-get nil "EPRESENT_SHOW_VIDEO")
      ;; advance to after properties if a file indicator is already here
      (when show-file
	(re-search-forward "[ \t]*:END:")
	(forward-line))
      (add-to-list 'epresent-fringe-overlays (make-overlay (point) (point)))
      (overlay-put (car epresent-fringe-overlays)
		   'before-string
		   (propertize " " 'display '(right-fringe hollow-square))))
    ))

  
(defun epresent-slide-in-effect ()
  "Apply slide-in effect."
  (interactive)
  (setq slide-local (org-entry-get nil "EPRESENT_SLIDE_IN"))
  (if (string= slide-local "no")
      (setq slide-local nil)
    (setq slide-local t))
  (setq slide-global epresent-slide-in)
  (if (or slide-local (and (not slide-global) slide-local))
      (save-excursion
	(goto-char (point-min))
	(forward-line)
	;; if there is a drawer, skip it
	(if (looking-at "[ \t]*:PROPERTIES:")
	    (re-search-forward "^[ \t]*:END:[ \r\n]" nil t))
	(setq ov (make-overlay (point) (point)))
	(dotimes (i epresent-slide-in-lines)
	  (progn
	    (if (eq i 1) (sit-for epresent-slide-in-pause))
	    (setq str (make-string (- epresent-slide-in-lines i) 10))
	    (overlay-put ov 'after-string str)
	    (sit-for (/ epresent-slide-in-duration epresent-slide-in-lines))))
	(delete-overlay ov))))

(defun epresent-top ()
  "Present the first outline heading."
  (interactive)
  (widen)
  (goto-char (point-min))
  (setq epresent-page-number 1)
  (epresent-current-page))

(defun epresent-next-page ()
  "Present the next outline heading."
  (interactive)
  (epresent-goto-top-level)
  (widen)
  (when (if (< (or (ignore-errors (org-reduced-level (org-current-level))) 0)
               epresent-frame-level)
            (outline-next-heading)
          (org-get-next-sibling))
    (cl-incf epresent-page-number))
  (epresent-current-page)
  (epresent-slide-in-effect)
  (if epresent-indicators (epresent-show-indicators))
  (epresent-show-file-auto))

(defun epresent-previous-page ()
  "Present the previous outline heading."
  (interactive)
  (epresent-goto-top-level)
  (widen)
  (org-content)
  (if (< (or (ignore-errors (org-reduced-level (org-current-level))) 0)
         epresent-frame-level)
      (outline-previous-heading)
    (org-get-last-sibling))
  (when (> epresent-page-number 1)
    (cl-decf epresent-page-number))
  (epresent-current-page))

(defun epresent-next-subheading ()
  "Advance to next subheading, unhiding it if hidden."
  (interactive)
  (org-next-visible-heading 1)
  (org-show-subtree))

(defun epresent-previous-subheading ()
  "Go back to previous subheading, possibly hiding the current one."
  (interactive)
  (when (> (org-current-level) 1)
    (outline-hide-subtree))
  (org-next-visible-heading -1) ; -1 means previous
  (if (> (org-current-level) 1) ; show if we found a subheading
      (org-show-subtree)))

(defun epresent-clean-overlays (&optional start end)
  (interactive)
  (let (kept)
    (dolist (ov epresent-overlays)
      (if (or (and start (overlay-start ov) (<= (overlay-start ov) start))
              (and end   (overlay-end   ov) (>= (overlay-end   ov) end)))
          (push ov kept)
        (delete-overlay ov)))
    (setq epresent-overlays kept)))

(defun epresent-clean-fringe-overlays ()
  "Remove file and video indicators from fringe."
  (interactive)
  (dolist (ov epresent-fringe-overlays)
    (delete-overlay ov)))

(defun epresent-quit ()
  "Quit the current presentation."
  (interactive)
  (run-hooks 'epresent-stop-presentation-hook)
  (org-remove-latex-fragment-image-overlays)
  ;; restore the user's Org-mode variables
  (remove-hook 'org-src-mode-hook 'epresent-setup-src-edit)
  (setq org-inline-image-overlays epresent-inline-image-overlays)
  (setq org-src-fontify-natively epresent-src-fontify-natively)
  (setq org-hide-emphasis-markers epresent-hide-emphasis-markers)
  (set-display-table-slot standard-display-table
                          'selective-display epresent-outline-ellipsis)
  (setq org-pretty-entities epresent-pretty-entities)
  (remove-hook 'org-babel-after-execute-hook 'epresent-refresh)
  (when (string= "EPresent" (frame-parameter nil 'title))
    (delete-frame (selected-frame)))
  (when epresent--org-file
   (kill-buffer (get-file-buffer epresent--org-file))
      (when (file-exists-p epresent--org-file)
        (delete-file epresent--org-file))
    )
  (when epresent--org-buffer
    (set-buffer epresent--org-buffer))
  (org-mode)
  (if epresent--org-restriction
      (apply #'narrow-to-region epresent--org-restriction)
    (widen))
  (hack-local-variables)
  ;; delete all epresent overlays
  (epresent-clean-overlays)
  (epresent-clean-fringe-overlays))
  
(defun epresent-increase-font ()
  "Increase the presentation font size."
  (interactive)
  (dolist (face
           '(epresent-heading-face epresent-content-face epresent-fixed-face))
    (set-face-attribute face nil :height (1+ (face-attribute face :height)))))

(defun epresent-decrease-font ()
  "Decrease the presentation font size."
  (interactive)
  (dolist (face
           '(epresent-heading-face epresent-content-face epresent-fixed-face))
    (set-face-attribute face nil :height (1- (face-attribute face :height)))))

(defun epresent-fontify ()
  "Overlay additional presentation faces to Org-mode."
  (save-excursion
    ;; hide all comments
    (goto-char (point-min))
    (while (re-search-forward
            "^[ \t]*#\\(\\+\\(author\\|title\\|date\\):\\)?.*\n"
            nil t)
      (cond
       ;; this avoids hiding title, author, or date
       ((and (match-string 2)
             (save-match-data
               (string-match (regexp-opt '("title" "author" "date"))
                             (match-string 2)))))
       ;; special handling of #+results
       ((and (match-string 2)
	     (save-match-data
	       (string-match org-babel-results-keyword (match-string 2))))
        ;; This pulls back the end of the hidden overlay by one to
        ;; avoid hiding image results of code blocks.  I'm not sure
        ;; why this is required, or why images start on the preceding
        ;; newline, but not knowing why doesn't make it less true.
        (push (make-overlay (match-beginning 0) (- (match-end 0) 1))
              epresent-overlays)
        (overlay-put (car epresent-overlays) 'invisible 'epresent-hide))
       ((save-match-data
	  (string-match "^[ \t]*#\\+attr_org:.*?\n" (match-string 0)))
        (push (make-overlay (match-beginning 0) (- (match-end 0) 1))
              epresent-overlays)
        (overlay-put (car epresent-overlays) 'invisible 'epresent-hide))
       ;; this hides all other comments
       (t (push (make-overlay (match-beginning 0) (match-end 0))
                epresent-overlays)
          (overlay-put (car epresent-overlays) 'invisible 'epresent-hide))))
    ;; page title faces and heading/subheading faces
    (goto-char (point-min))
    (while (re-search-forward "^\\(*+\\)\\([ \t]+\\)\\(.*\\)$" nil t)
      ;; hide the first match, that is the stars
      (push (make-overlay (match-beginning 1) (or (match-end 2)
                                                 (match-end 1)))
           epresent-overlays)
      (overlay-put (car epresent-overlays) 'invisible 'epresent-hide)
      ;; apply faces to heading and subheading
      (push (make-overlay (match-beginning 3) (match-end 3)) epresent-overlays)
      (if (> (length (match-string 1)) 1)
          (overlay-put (car epresent-overlays) 'face 'epresent-subheading-face)
	  (overlay-put (car epresent-overlays) 'face 'epresent-heading-face)))
    ;; fancy bullet points
    (org-superstar-mode)
    ;; hide todos
    (when epresent-hide-todos
      (goto-char (point-min))
      (while (re-search-forward org-todo-line-regexp nil t)
        (when (match-string 2)
          (push (make-overlay (match-beginning 2) (1+ (match-end 2)))
                epresent-overlays)
          (overlay-put (car epresent-overlays) 'invisible 'epresent-hide))))
    ;; hide tags
    (when epresent-hide-tags
      (goto-char (point-min))
      (while (re-search-forward
              (org-re "^\\*+.*?\\([ \t]+:[[:alnum:]_@#%:]+:\\)[ \r\n]")
              nil t)
        (push (make-overlay (match-beginning 1) (match-end 1)) epresent-overlays)
        (overlay-put (car epresent-overlays) 'invisible 'epresent-hide)))
    ;; hide properties
    (when epresent-hide-properties
      (goto-char (point-min))
      (while (re-search-forward org-drawer-regexp nil t)
        (let ((beg (match-beginning 0))
              (end (re-search-forward
                    "^[ \t]*:END:[ \r\n]"
                    (save-excursion (outline-next-heading) (point)) t)))
          (push (make-overlay beg end) epresent-overlays)
          (overlay-put (car epresent-overlays) 'invisible 'epresent-hide))))
    (dolist (el '("title" "author" "date"))
      (goto-char (point-min))
      (when (re-search-forward (format "^\\(#\\+%s:[ \t]*\\)[ \t]*\\(.*\\)$" el) nil t)
        (push (make-overlay (match-beginning 1) (match-end 1)) epresent-overlays)
        (overlay-put (car epresent-overlays) 'invisible 'epresent-hide)
        (push (make-overlay (match-beginning 2) (match-end 2)) epresent-overlays)
        (overlay-put
         (car epresent-overlays) 'face (intern (format "epresent-%s-face" el)))))
    ;; inline images
    (org-display-inline-images)))

(defun epresent-refresh ()
  (interactive)
  (epresent-clean-overlays (point-min) (point-max))
  (epresent-fontify)
  )

(defun epresent-setup-src-edit ()
  (setq cursor-type 'box))

(defun epresent-flash-cursor ()
  (setq cursor-type 'hollow)
  (sit-for 0.5)
  (setq cursor-type nil))

(defun epresent-next-src-block (&optional arg)
  (interactive "P")
  (org-babel-next-src-block arg)
  (epresent-flash-cursor))

(defun epresent-previous-src-block (&optional arg)
  (interactive "P")
  (org-babel-previous-src-block arg)
  (epresent-flash-cursor))

(defun epresent-toggle-hide-src-blocks (&optional arg)
  (interactive "P")
  (cl-labels
      ((boundaries
        ()
        (let ((head (org-babel-where-is-src-block-head)))
          (if head
              (save-excursion
                (goto-char head)
                (looking-at org-babel-src-block-regexp)
                (list (match-beginning 5) (match-end 5)))
            (error "no source block to hide at %d" (point)))))
       (toggle
        ()
        (cl-destructuring-bind (beg end) (boundaries)
          (let ((ovs (cl-remove-if-not
                      (lambda (ov) (overlay-get ov 'epresent-hidden-src-block))
                      (overlays-at beg))))
            (if ovs
                (unless (and epresent-src-block-toggle-state
                             (eq epresent-src-block-toggle-state :hide))
                  (progn
                    (mapc #'delete-overlay ovs)
                    (setq epresent-overlays
                          (cl-set-difference epresent-overlays ovs))))
              (unless (and epresent-src-block-toggle-state
                           (eq epresent-src-block-toggle-state :show))
                (progn
                  (push (make-overlay beg end) epresent-overlays)
                  (overlay-put (car epresent-overlays)
                               'epresent-hidden-src-block t)
                  (overlay-put (car epresent-overlays)
                               'invisible 'epresent-hide))))))))
    (if arg (toggle)               ; only toggle the current src block
      (save-excursion              ; toggle all source blocks
        (goto-char (point-min))
        (while (re-search-forward org-babel-src-block-regexp nil t)
          (goto-char (1- (match-end 5)))
          (toggle))))
    (redraw-display)))

(defun epresent-toggle-hide-src-block (&optional arg)
  (interactive "P")
  (epresent-toggle-hide-src-blocks t))

(defun epresent-show-file (&optional filename size below)
  "Show FILENAME file by splitting the buffer. If FILENAME is not
  given, the value of the EPRESENT_SHOW_FILE property is used.

  If BELOW is nil (default), the new buffer is to the right of
  the current buffer, otherwise it is below. If not provided, the
  EPRESENT_SHOW_BELOW property is looked up.

  SIZE is the size of the new buffer, in lines when it is below,
  and in columns when it is to the right. If not provided, the
  EPRESENT_SHOW_SIZE property is used. If nothing is found, SIZE
  defaults to half the window.

  The file is fit to width or height if it is a PDF or image.

  After the file is displayed and fit, focus is returned to the
  EPresent window, and changing the frame will delete the
  auxiliary window showing the file.)

  The file buffer is refreshed anytime it is displayed."
  (interactive)
  (delete-other-windows)
  ;; if any of the arguments is not set, look at properties:
  (if (not filename)
      (setq filename (org-entry-get nil "EPRESENT_SHOW_FILE")))
  (when (not size)
    (setq size (org-entry-get nil "EPRESENT_SHOW_SIZE"))
    ;; convert to number, as properties are strings:
    (if (stringp size)
	(setq size (string-to-number size))))
  (if (not below)
      (setq below (org-entry-get nil "EPRESENT_SHOW_BELOW")))
  ;; negate size if not nil to conform to split-window-* conventions
  (if size (setq size (- size))) 
  (epresent-clean-fringe-overlays)
  (setq epresent-presentation-window (selected-window))
  (if below
      (setq epresent-auxiliary-window (split-window-below size))
    (setq epresent-auxiliary-window (split-window-right size)))
  (select-window epresent-auxiliary-window)
  (find-file filename)
  (setq mode-line-format (epresent-get-mode-line))
  (revert-buffer t t t)
  ;; set width of PDF and image files
  (if (string= "pdf" (file-name-extension filename))
      (pdf-view-fit-width-to-window))
  (if (and (boundp 'image-mode) (eq major-mode image-mode))
      (if below
	  (image-transform-fit-to-height)
	(image-transform-fit-to-width)))
  (select-window epresent-presentation-window))

(defun epresent-show-file-auto ()
  "Helper function to show an image automatically upon page
display."
  (if (org-entry-get nil "EPRESENT_SHOW_AUTO")
      (epresent-show-file)))
  

(defun epresent-show-video (&optional filename mute)
  "Show a video in fullscreen mode.

FILENAME is the video filename. If not provided, the value of the
EPRESENT_SHOW_VIDEO property is used.

If MUTE is non nil, the audio is muted. If not provided, the
value of the EPRESENT_MUTE property is used.

This function uses vlc."
  (interactive)
  ;; if no filename or mute, try to get them from properties:
  (if (not filename)
      (setq filename (org-entry-get nil "EPRESENT_SHOW_VIDEO")))
  (if (not mute)
      (setq mute (org-entry-get nil "EPRESENT_MUTE")))
  (if mute
      (setq mute " --no-audio ")
    (setq mute ""))
  (set-frame-parameter nil 'fullscreen nil)
  (shell-command (concat "cvlc -f --no-osd " mute filename))
  (delete-other-windows)
  (set-frame-parameter nil 'fullscreen 'fullboth)
  )

(defun epresent-estimate-time ()
  "Estimates the time needed to read all speaker notes, assuming
a reading speed of 125 words per minute. The estimated time and
the number of words in speaker notes are displayed in the
minibuffer."
  (interactive)
  (setq speaker-words 0)
  (org-map-entries
   (lambda ()
     (setq this-headline (downcase (org-entry-get nil "ITEM")))
     (when (string= this-headline "speaker notes")
       (save-excursion
	 (org-mark-subtree)
	 (setq speaker-words
	       (+ speaker-words (count-words (point) (mark))))
	 (deactivate-mark)))))
  (setq speaker-time (ceiling (/ (float speaker-words) 125)))
  (message (concat
	    "Estimated speaking time in minutes: "
	    (number-to-string speaker-time)
	    " ("
	    (number-to-string speaker-words)
	    " words)")))

(defvar epresent-mode-map
  (let ((map (make-keymap)))
    (suppress-keymap map)
    ;; line movement
    (define-key map "j" 'scroll-up)
    (define-key map [down] 'scroll-up)
    (define-key map "k" 'scroll-down)
    (define-key map [up] 'scroll-down)
    ;; page movement
    (define-key map " " 'epresent-next-page)
    (define-key map "n" 'epresent-next-page)
    (define-key map "f" 'epresent-next-page)
    (define-key map [right] 'epresent-next-page)
    (define-key map [next] 'epresent-next-page)
    (define-key map "p" 'epresent-previous-page)
    (define-key map "b" 'epresent-previous-page)
    (define-key map [left] 'epresent-previous-page)
    (define-key map [prior] 'epresent-previous-page)
    (define-key map [backspace] 'epresent-previous-page)
    (define-key map "v" 'epresent-jump-to-page)
    ;; within page functions
    (define-key map "c" 'epresent-next-src-block)
    (define-key map "C" 'epresent-previous-src-block)
    (define-key map "e" 'org-edit-src-code)
    (define-key map [f5] 'epresent-edit-text) ; Another [f5] exits edit mode.
    (define-key map "x" 'org-babel-execute-src-block)
    (define-key map "r" 'epresent-refresh)
    (define-key map "R" 'redraw-display)
    (define-key map "g" 'epresent-refresh)
    (define-key map "N" 'epresent-next-subheading)
    (define-key map "P" 'epresent-previous-subheading)
    (define-key map "i" 'epresent-show-file)
    (define-key map "I" 'epresent-show-video)
    (define-key map "K" 'delete-other-windows)
    ;; global controls
    (define-key map "q" 'epresent-quit)
    (define-key map "1" 'epresent-top)
    (define-key map "s" 'epresent-toggle-hide-src-blocks)
    (define-key map "S" 'epresent-toggle-hide-src-block)
    (define-key map "t" 'epresent-top)
    map)
  "Local keymap for EPresent display mode.")

(define-derived-mode epresent-mode org-mode "EPresent"
  "Lalala."
  ;; make Org-mode be as pretty as possible
  (add-hook 'org-src-mode-hook 'epresent-setup-src-edit)
  (setq epresent-inline-image-overlays org-inline-image-overlays)
  (setq epresent-src-fontify-natively org-src-fontify-natively)
  (setq org-src-fontify-natively t)
  (setq org-fontify-quote-and-verse-blocks t)
  (setq epresent-hide-emphasis-markers org-hide-emphasis-markers)
  (setq org-hide-emphasis-markers t)
  (setq epresent-outline-ellipsis
        (display-table-slot standard-display-table 'selective-display))
  (set-display-table-slot standard-display-table 'selective-display [32])
  (setq epresent-pretty-entities org-pretty-entities)
  (setq org-hide-pretty-entities t)
  (setq mode-line-format (epresent-get-mode-line))
  (add-hook 'org-babel-after-execute-hook 'epresent-refresh)
  (condition-case ex
      (let ((org-format-latex-options
             (plist-put (copy-tree org-format-latex-options)
                        :scale epresent-format-latex-scale)))
        (org-preview-latex-fragment '(16)))
    ('error
     (message "Unable to imagify latex [%s]" ex)))
  (set-face-attribute 'default epresent--frame :height epresent-text-scale)
  ;; fontify the buffer
  (add-to-invisibility-spec '(epresent-hide))
  ;; remove flyspell overlays
  (flyspell-mode-off)
  (epresent-fontify)
  ;; hide headings with EPRESENT_HIDE tag or marked as "speaker notes"
  (org-map-entries (lambda ()
		     (when (or
			    (org-entry-get nil "EPRESENT_HIDE")
			    (string= (downcase (org-entry-get nil "ITEM")) "speaker notes"))
		       (org-mark-subtree)
		       ;; we make things insvisile only until mark-1
		       ;; to leave a newline visible, as a separator
		       ;; betwen this heading and the next
		       (push (make-overlay (point) (- (mark) 1)) epresent-overlays)
		       (overlay-put (car epresent-overlays)
				    'invisible
				    'epresent-hide)
		       (deactivate-mark))))
  ;; reset the auxiliary window object
  (setq epresent-auxiliary-window nil))

(defvar epresent-edit-map (let ((map (copy-keymap org-mode-map)))
                            (define-key map [f5] 'epresent-refresh)
                            map)
  "Local keymap for editing EPresent presentations.")

(defun epresent-edit-text (&optional arg)
  "Write in EPresent presentation."
  (interactive "p")
  (let ((prior-cursor-type (cdr (assoc 'cursor-type (frame-parameters)))))
    (set-frame-parameter nil 'cursor-type t)
    (use-local-map epresent-edit-map)
    (set-transient-map
     epresent-edit-map
     (lambda () (not (equal [f5] (this-command-keys))))
     (lambda ()
       (use-local-map epresent-mode-map)
       (set-frame-parameter nil 'cursor-type prior-cursor-type)))))

;;;###autoload
(defun epresent-run ()
  "Present an Org-mode buffer."
  (interactive)
  (unless (eq major-mode 'epresent-mode)
    (unless (eq major-mode 'org-mode)
      (error "EPresent can only be used from Org Mode"))
    (setq epresent--org-buffer (current-buffer))
    ;; To present narrowed region use temporary buffer
    (when (and (or (> (point-min) (save-restriction (widen) (point-min)))
                   (< (point-max) (save-restriction (widen) (point-max))))
               (save-excursion (goto-char (point-min)) (org-at-heading-p)))
      (let ((title (nth 4 (org-heading-components))))
        (setq epresent--org-restriction (list (point-min) (point-max)))
        (require 'ox-org)
        (setq epresent--org-file (org-org-export-to-org nil 'subtree))
        (find-file epresent--org-file)
        (goto-char (point-min))
        (insert (format "#+Title: %s\n\n" title))))
    (setq epresent-frame-level (epresent-get-frame-level))
    (epresent--get-frame)
    (epresent-mode)
    (set-buffer-modified-p nil)
    (run-hooks 'epresent-start-presentation-hook)))

(define-key org-mode-map [f5]  'epresent-run)
(define-key org-mode-map [f12] 'epresent-run)

(provide 'epresent)
;;; epresent.el ends here
