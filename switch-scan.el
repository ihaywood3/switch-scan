;;; -*- lexical-binding: t -*-
; switch-scan.el - Emacs support for switch scanning input
					;
; This program is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 3 of the License, or
; (at your option) any later version.

; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more
; You should have received a copy of the GNU General Public License
; along with this program.  If not, see <https://www.gnu.org/licenses/>.



(defgroup switch-scan nil
  "configuration for switch scanning"
  :group 'hardware)

(defcustom switch-scan-line-pause 600
  "milliseconds to pause between each scanning line"
  :type 'integer)

(defcustom switch-scan-item-pause 400
  "milliseconds to pause between each scanning item"
  :type 'integer)

(defcustom switch-scan-default-keyboard
  '(("t" "o" "e" "f" "c" "d" "b" "y" "x")
    ("a" "h" "n" "p" "u" "l" "w" "v" "q")
    ("i" "s" "r" "m" ("SPC" . "<SPC>") "g" "k" "z" "j")
    ("0" "1" "2" "3" "4" "5" "6" "7" "8" "9")
    ("." ":" "?" "," "{" "}" "<" ">" "&" "^" "~")
    ("-" "=" "+" "(" ")" "[" "]" "%" "_" "!" "$")
    (";" "/" "'" "\"" "\\" "#" "@" "*" "|" "`")
    (("CTRL" . control) ("RET" . "<RET>") ("BKSPC" . "<backspace>") ("TAB" . "<tab>") ("META" . meta) ("DEL" . "<DEL>")
     ("UP" . "<up>") ("DOWN" . "<down>") ("LEFT" . "<left>") ("RIGHT" . "<right>")
     ("SHIFT" . shift)))
  "keyboard definition for all major modes unless otherwise defined in switch-scan-specific-keyboards"
  :type 'sexp)

(defcustom switch-scan-specific-keyboards nil
  "an alist of specific keyboards for different major modes"
  :type 'sexp)

(defcustom switch-scan-driver-path "/home/ian/switch-scan/joystick.py"
  "path to driver script to receive switch scanning events"
  :type '(file :must-match t))

(defcustom switch-scan-joystick 0
  "which joystick to use (starting at 0)"
  :type 'integer)

(defcustom switch-scan-joystick-button 1
  "which joystick button to use (starting at 0)"
  :type 'integer)

; "private" variables

(defvar sscan-thread nil)

(defvar sscan-thread-flag t
  "flag to signal when the thread stops")

(defvar sscan-pressed-flag nil
  "flag set when button pressed")

(defvar sscan-unpressed-flag nil
  "flag set when button released")
;; we use two flags so we can detect if the button has been pressed and released in
;; quick succession

(defvar sscan-selected nil
  "value of the selected keyboard item")

(defun switch-scan ()
  "start switch scanning"
  (interactive)
  (let ((sscan-buffer
	 (generate-new-buffer " *switch-scan*"))
	(sscan-window ;; one-line window at bottom of screen
	 (split-window (frame-root-window) -1))
	(sscan-process (make-process
			:name "sscan-driver"
			:command (list
				  "/usr/bin/python3"
				  switch-scan-driver-path
				  (number-to-string switch-scan-joystick)
				  (number-to-string switch-scan-joystick-button))
			:connection-type 'pipe
			:noquery nil
			:filter #'(lambda (p s) ;; subprocess sends back events as sexps
				    (eval (car (read-from-string s))))
			:sentinel #'(lambda (p s) ;; end sscan-cycle if subprocess dies
				      (setq sscan-thread-flag nil)))))
    ;; configure window
    (with-current-buffer sscan-buffer
      (setq mode-line-format nil)
      (setq buffer-read-only t)
      (setq buffer-undo-list t)
      (setq window-size-fixed 'height))
    (set-window-buffer sscan-window sscan-buffer)
    (set-window-dedicated-p sscan-window t)
    ;; start background thread
    (setq sscan-thread-flag t)
    (make-thread
     #'(lambda ()
	 (sscan-cycle sscan-buffer sscan-window sscan-process))
     "*sscan-cycle*")))

(defun switch-scan-stop ()
  "stop switch scanning"
  (interactive)
  (setq sscan-thread-flag nil))

(defun sscan-cycle (sscan-buffer sscan-window sscan-process)
  "display keyboard on ongoing cycle"
  (let ((meta-key nil) (control-key nil) (shift-key nil) (alt-key nil) (super-key nil)
	(hyper-key nil))
    (while sscan-thread-flag
      (dolist (idx switch-scan-default-keyboard)
	;; FUTURE select a keyboard based on current buffer's major mode
	(sscan-buffer-set -1) ;; display keyboard line with no item selected  
	(setq sscan-pressed-flag nil)
	(setq sscan-unpressed-flag nil)      
	(sleep-for (/ switch-scan-line-pause 1000.0))
	(when sscan-pressed-flag ;; user has selected this line 
	  (let ((sel 0) (flag t))
	    (while flag
	      (when (= sel (1- (length idx))) (setq flag nil))
	      (sscan-buffer-set sel) ;; redisplay line with each irem selected 
	      (setq sscan-pressed-flag nil)
	      (setq sscan-unpressed-flag nil)
	      (sleep-for (/ switch-scan-item-pause 1000.0))
	      (when sscan-pressed-flag ;; user has selected this item
		(setq flag nil)
		(setq sscan-pressed-flag nil)
		(setq sscan-unpressed-flag nil)
		(cond
		 ((eq sscan-selected 'shift) ;; modifier key chosen 
		  (setq shift-key t))
		 ((eq sscan-selected 'meta)
		  (setq meta-key t))
		 ((eq sscan-selected 'alt)
		  (setq alt-key t))
		 ((eq sscan-selected 'super)
		  (setq super-key t))
		 ((eq sscan-selected 'hyper)
		  (setq hyper-key t))
		 ((eq sscan-selected 'control)
		  (setq control-key t))
		 ;; "standard" string defined keys
		 ((stringp sscan-selected)
		  ;; if modifiers in effect add prefixes to key definition 
		  (when meta-key
		    (setq sscan-selected (concat "M-" sscan-selected)))
		  (when control-key
		    (setq sscan-selected (concat "C-" sscan-selected)))
		  (when alt-key
		    (setq sscan-selected (concat "A-" sscan-selected)))
		  (when super-key
		    (setq sscan-selected (concat "s-" sscan-selected)))
		  (when hyper-key
		    (setq sscan-selected (concat "H-" sscan-selected)))
		  ;; reset the modifier flags
		  (setq shift-key nil)
		  (setq meta-key nil)
		  (setq control-key nil)
		  (setq alt-key nil)
		  (setq super-key nil)
		  (setq hyper-key nil)
		  ;; synthesise a keyboard event 
		  (setq unread-command-events
		      (nreverse (cons (cons t
					    (car (listify-key-sequence (kbd sscan-selected))))
				      (nreverse unread-command-events)))))
	       ;; keybard item is a function - call it
		 ((functionp sscan-selected)
		  (funcall sscan-selected))))
	      (setq sel (1+ sel))
	       ))))))
  ;; main loop has ended - cleanup
  (delete-window sscan-window)
  (kill-buffer sscan-buffer)
  (if (processp sscan-process)
      (kill-process sscan-process)))

(defmacro sscan-buffer-set (sel)
  "set the scanning buffer. An unhygienic macro only for use inside sscan-cycle"
  `(with-current-buffer sscan-buffer
     (let ((buffer-read-only nil))
       (erase-buffer)
       (insert (sscan-make-line idx ,sel shift-key)))
     (redisplay)
     ))

(defun sscan-make-line (line sel shift-key)
  "create a text line for display from keyboard definition"
  (let ((n -1))
    (mapconcat
     #'(lambda (x)
	 (setq n (1+ n))
	 (propertize
	  (concat " "
		  (cond
		   ((stringp x)
		    (when shift-key (setq x (upcase x)))
		    (when (= sel n) (setq sscan-selected x))
		    x)
		   ((consp x)
		    (when (= sel n) (setq sscan-selected (cdr x)))
		    (car x)))
		  " ")
	  'face `(:reverse-video ,(= sel n))))
   line
   "")))

(provide 'switch-scan)

;;; switch-scan.el ends
  
