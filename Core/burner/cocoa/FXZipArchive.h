/*****************************************************************************
 **
 ** FinalBurn X: Port of FinalBurn to OS X
 ** https://github.com/pokebyte/FinalBurnX
 ** Copyright (C) 2014 Akop Karapetyan
 **
 ** This program is free software; you can redistribute it and/or modify
 ** it under the terms of the GNU General Public License as published by
 ** the Free Software Foundation; either version 2 of the License, or
 ** (at your option) any later version.
 **
 ** This program is distributed in the hope that it will be useful,
 ** but WITHOUT ANY WARRANTY; without even the implied warranty of
 ** MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 ** GNU General Public License for more details.
 **
 ** You should have received a copy of the GNU General Public License
 ** along with this program; if not, write to the Free Software
 ** Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 **
 ******************************************************************************
 */
#import <Foundation/Foundation.h>

#import "FXZipFile.h"

#include "unzip.h"

@interface FXZipArchive : NSObject
{
    @private
    unzFile zipFile;
    NSArray *fileCache;
}

@property (nonatomic, strong) NSString *path;

- (instancetype)initWithPath:(NSString *)path
                       error:(NSError **)error;
- (NSArray *)files;
- (NSUInteger)fileCount;
- (FXZipFile *)findFileWithCRC:(NSUInteger)crc;
- (FXZipFile *)findFileNamed:(NSString *)filename
              matchExactPath:(BOOL)exactPath;
- (FXZipFile *)findFileNamedAnyOf:(NSArray *)filenames
                   matchExactPath:(BOOL)exactPath;
- (UInt32)readFileWithCRC:(NSUInteger)crc
               intoBuffer:(void *)buffer
             bufferLength:(NSUInteger)length
                    error:(NSError **)error;

@end

enum {
    FXErrorLoadingArchive        = -100,
    FXErrorNavigatingArchive     = -101,
    FXErrorOpeningCompressedFile = -102,
    FXErrorReadingCompressedFile = -103,
};
