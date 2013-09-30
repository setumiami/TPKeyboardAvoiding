//
//  UIScrollView+TPKeyboardAvoidingAdditions.m
//  TPKeyboardAvoidingSample
//
//  Created by Michael Tyson on 30/09/2013.
//
//

#import "UIScrollView+TPKeyboardAvoidingAdditions.h"
#import <objc/runtime.h>

const CGFloat kCalculatedContentPadding = 10;

static const int kStateKey;

#define _UIKeyboardFrameEndUserInfoKey (&UIKeyboardFrameEndUserInfoKey != NULL ? UIKeyboardFrameEndUserInfoKey : @"UIKeyboardBoundsUserInfoKey")

@interface TPKeyboardAvoidingState : NSObject
@property (nonatomic, assign) UIEdgeInsets priorInset;
@property (nonatomic, assign) UIEdgeInsets priorScrollIndicatorInsets;
@property (nonatomic, assign) BOOL         keyboardVisible;
@property (nonatomic, assign) CGRect       keyboardRect;
@property (nonatomic, assign) CGSize       priorContentSize;
@end

@implementation UIScrollView (TPKeyboardAvoidingAdditions)

- (TPKeyboardAvoidingState*)keyboardAvoidingState {
    TPKeyboardAvoidingState *state = objc_getAssociatedObject(self, &kStateKey);
    if ( !state ) {
        state = [[TPKeyboardAvoidingState alloc] init];
        objc_setAssociatedObject(self, &kStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
#if !__has_feature(objc_arc)
        [state release];
#endif
    }
    return state;
}

- (void)TPKeyboardAvoiding_keyboardWillShow:(NSNotification*)notification {
    UIView *firstResponder = [self findFirstResponderBeneathView:self];
    if ( !firstResponder ) {
        // No child view is the first responder - nothing to do here
        return;
    }
    
    TPKeyboardAvoidingState *state = self.keyboardAvoidingState;
    state.keyboardRect = [[[notification userInfo] objectForKey:_UIKeyboardFrameEndUserInfoKey] CGRectValue];
    state.keyboardVisible = YES;
    state.priorInset = self.contentInset;
    state.priorScrollIndicatorInsets = self.scrollIndicatorInsets;
    
    state.priorContentSize = self.contentSize;
    
    if ( CGSizeEqualToSize(self.contentSize, CGSizeZero) ) {
        // Set the content size, if it's not set
        self.contentSize = [self calculatedContentSizeFromSubviewFrames];
    }
    
    // Shrink view's inset by the keyboard's height, and scroll to show the text field/view being edited
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationCurve:[[[notification userInfo] objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue]];
    [UIView setAnimationDuration:[[[notification userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] floatValue]];
    
    self.contentInset = [self contentInsetForKeyboard];
    
    [self setContentOffset:CGPointMake(self.contentOffset.x,
                                       [self idealOffsetForView:firstResponder
                                                      withViewingAreaHeight:state.keyboardRect.origin.y - [self convertPoint:self.bounds.origin toView:nil].y])
                  animated:YES];
    [self setScrollIndicatorInsets:self.contentInset];
    
    [UIView commitAnimations];
}

- (void)TPKeyboardAvoiding_keyboardWillHide:(NSNotification*)notification {
    TPKeyboardAvoidingState *state = self.keyboardAvoidingState;
    
    if ( !state.keyboardVisible ) {
        return;
    }
    
    state.keyboardRect = CGRectZero;
    state.keyboardVisible = NO;
    
    // Restore dimensions to prior size
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationCurve:[[[notification userInfo] objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue]];
    [UIView setAnimationDuration:[[[notification userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] floatValue]];
    self.contentSize = state.priorContentSize;
    self.contentInset = state.priorInset;
    self.scrollIndicatorInsets = state.priorScrollIndicatorInsets;
    [UIView commitAnimations];
}

- (void)updateContentInset {
    TPKeyboardAvoidingState *state = self.keyboardAvoidingState;
    if ( state.keyboardVisible ) {
        self.contentInset = [self contentInsetForKeyboard];
    }
}

- (void)updateFromContentSizeChange {
    TPKeyboardAvoidingState *state = self.keyboardAvoidingState;
    if ( state.keyboardVisible ) {
		state.priorContentSize = self.contentSize;
        self.contentInset = [self contentInsetForKeyboard];
    }
}

#pragma mark - Utilities

- (BOOL)focusNextTextField {
    UIView *firstResponder = [self findFirstResponderBeneathView:self];
    if ( !firstResponder ) {
        return NO;
    }
    
    CGFloat minY = CGFLOAT_MAX;
    UIView *view = nil;
    [self findTextFieldAfterTextField:firstResponder beneathView:self minY:&minY foundView:&view];
    
    if ( view ) {
        [view becomeFirstResponder];
        return YES;
    }
    
    return NO;
}

-(void)scrollToActiveTextField {
    TPKeyboardAvoidingState *state = self.keyboardAvoidingState;
    
    if ( !state.keyboardVisible ) return;
    
    CGFloat visibleSpace = self.bounds.size.height - self.contentInset.top - self.contentInset.bottom;
    
    CGPoint idealOffset = CGPointMake(0, [self idealOffsetForView:[self findFirstResponderBeneathView:self] withViewingAreaHeight:visibleSpace]);
    
    [self setContentOffset:idealOffset animated:YES];
}

#pragma mark - Helpers

- (UIView*)findFirstResponderBeneathView:(UIView*)view {
    // Search recursively for first responder
    for ( UIView *childView in view.subviews ) {
        if ( [childView respondsToSelector:@selector(isFirstResponder)] && [childView isFirstResponder] ) return childView;
        UIView *result = [self findFirstResponderBeneathView:childView];
        if ( result ) return result;
    }
    return nil;
}

- (void)findTextFieldAfterTextField:(UIView*)priorTextField beneathView:(UIView*)view minY:(CGFloat*)minY foundView:(UIView**)foundView {
    // Search recursively for text field or text view below priorTextField
    CGFloat priorFieldOffset = CGRectGetMinY([self convertRect:priorTextField.frame fromView:priorTextField.superview]);
    for ( UIView *childView in view.subviews ) {
        if ( childView.hidden ) continue;
        if ( ([childView isKindOfClass:[UITextField class]] || [childView isKindOfClass:[UITextView class]]) ) {
            CGRect frame = [self convertRect:childView.frame fromView:view];
            if ( childView != priorTextField && CGRectGetMinY(frame) >= priorFieldOffset && CGRectGetMinY(frame) < *minY ) {
                *minY = CGRectGetMinY(frame);
                *foundView = childView;
            }
        } else {
            [self findTextFieldAfterTextField:priorTextField beneathView:childView minY:minY foundView:foundView];
        }
    }
}

- (void)assignTextDelegateForViewsBeneathView:(UIView*)view {
    for ( UIView *childView in view.subviews ) {
        if ( ([childView isKindOfClass:[UITextField class]] || [childView isKindOfClass:[UITextView class]]) ) {
            [self initializeView:childView];
        } else {
            [self assignTextDelegateForViewsBeneathView:childView];
        }
    }
}

-(CGSize)calculatedContentSizeFromSubviewFrames {
    CGRect rect = CGRectZero;
    for ( UIView *view in self.subviews ) {
        rect = CGRectUnion(rect, view.frame);
    }
    rect.size.height += kCalculatedContentPadding;
    return rect.size;
}

- (UIEdgeInsets)contentInsetForKeyboard {
    UIEdgeInsets newInset = self.contentInset;
    CGRect keyboardRect = [self keyboardRect];
    newInset.bottom = keyboardRect.size.height - ((keyboardRect.origin.y+keyboardRect.size.height) - (self.bounds.origin.y+self.bounds.size.height));
    return newInset;
}

-(CGFloat)idealOffsetForView:(UIView *)view withViewingAreaHeight:(CGFloat)viewAreaHeight {
    
    // Convert the rect to get the view's distance from the top of the scrollView.
    CGRect rect = [view convertRect:view.bounds toView:self];
    
    // Set starting offset to that point
    CGFloat offset = rect.origin.y;
    
    
    if ( self.contentSize.height - offset < viewAreaHeight ) {
        // Scroll to the bottom
        offset = self.contentSize.height - viewAreaHeight;
    } else {
        if ( view.bounds.size.height < viewAreaHeight ) {
            // Center vertically if there's room
            offset -= floor((viewAreaHeight-view.bounds.size.height)/2.0);
        }
        if ( offset + viewAreaHeight > self.contentSize.height ) {
            // Clamp to content size
            offset = self.contentSize.height - viewAreaHeight;
        }
    }
    
    if (offset < 0) offset = 0;
    
    return offset;
}

- (CGRect)keyboardRect {
    TPKeyboardAvoidingState *state = self.keyboardAvoidingState;
    CGRect keyboardRect = [self convertRect:state.keyboardRect fromView:nil];
    if ( keyboardRect.origin.y == 0 ) {
        CGRect screenBounds = [self convertRect:[UIScreen mainScreen].bounds fromView:nil];
        keyboardRect.origin = CGPointMake(0, screenBounds.size.height - keyboardRect.size.height);
    }
    return keyboardRect;
}

- (void)initializeView:(UIView*)view {
    if ( ([view isKindOfClass:[UITextField class]] || [view isKindOfClass:[UITextView class]]) && (![(id)view delegate] || [(id)view delegate] == self) ) {
        [(id)view setDelegate:self];
        
        if ( [view isKindOfClass:[UITextField class]] ) {
            UIView *otherView = nil;
            CGFloat minY = CGFLOAT_MAX;
            [self findTextFieldAfterTextField:view beneathView:self minY:&minY foundView:&otherView];
            
            if ( otherView ) {
                ((UITextField*)view).returnKeyType = UIReturnKeyNext;
            } else {
                ((UITextField*)view).returnKeyType = UIReturnKeyDone;
            }
        }
    }
}

@end


@implementation TPKeyboardAvoidingState
@end